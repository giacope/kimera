# frozen_string_literal: true

require_relative "support/syntax"
require_relative "support/syntax_types"

module Kimera
  module Memoization
    OR_WRITE_NODES = [
      SyntaxTypes::InstanceVariableOrWriteNode,
      SyntaxTypes::ClassVariableOrWriteNode,
      SyntaxTypes::GlobalVariableOrWriteNode
    ].freeze

    CONST_WRITE_NODES = [SyntaxTypes::ConstantWriteNode, SyntaxTypes::ConstantPathWriteNode].freeze

    SELF_OR_WRITE = {
      SyntaxTypes::InstanceVariableWriteNode => SyntaxTypes::InstanceVariableReadNode,
      SyntaxTypes::ClassVariableWriteNode => SyntaxTypes::ClassVariableReadNode,
      SyntaxTypes::GlobalVariableWriteNode => SyntaxTypes::GlobalVariableReadNode
    }.freeze

    Range =
      Struct.new(:start_offset, :end_offset, :reason, :holes) do
        def contains?(start, finish)
          return false unless start >= start_offset && finish <= end_offset
          Array(holes).none? { |first, last| start >= first && finish <= last }
        end
      end

    module_function

    def ranges(source)
      result = Kimera::Syntax.parse(source)
      return [] if result.failure?
      ranges = []
      visit(result.value, ranges)
      ranges
    end

    def visit(node, ranges)
      return unless node.is_a?(SyntaxTypes::Node)
      taint = taint(node)
      ranges << taint if taint
      node.compact_child_nodes.each { |child| visit(child, ranges) }
    end

    def taint(node)
      case node
      when *OR_WRITE_NODES then value(node, "memoized via ||=")
      when *CONST_WRITE_NODES then value(node, "constant assignment (computed once)")
      else cached(node)
      end
    end

    def value(node, reason)
      expression = node.value
      range(expression, reason) if expression
    end

    def cached(node)
      reader = SELF_OR_WRITE[node.class]
      return unless reader
      memoized(node, reader)
    end

    def memoized(node, reader)
      value = node.value
      return unless value.is_a?(SyntaxTypes::OrNode)
      left = value.left
      return unless left.is_a?(reader) && same?(node, left)
      range(value, "memoized via `x = x || ...`")
    end

    def same?(write, read)
      write.name == read.name
    end

    def range(node, reason)
      start, finish = span(node)
      Range.new(start, finish, reason, holes(node))
    end

    HOLE_NODES = [SyntaxTypes::DefNode, SyntaxTypes::LambdaNode].freeze

    def holes(node, holes = [])
      return holes unless node.is_a?(SyntaxTypes::Node)
      return body(node, holes) if HOLE_NODES.any? { |kind| node.is_a?(kind) }
      node.compact_child_nodes.each { |child| holes(child, holes) }
      holes
    end

    def body(node, holes)
      value = node.body
      holes << span(value) if value
      holes
    end

    def span(node)
      location = node.location
      start = location.start_offset
      [start, start + location.length]
    end
  end
end
