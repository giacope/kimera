# frozen_string_literal: true

require_relative "../support/syntax"
require_relative "../support/syntax_types"
require_relative "../support/deferral"

module Kimera
  class Memoization
    OR_WRITE_NODES = [
      SyntaxTypes::InstanceVariableOrWriteNode,
      SyntaxTypes::ClassVariableOrWriteNode,
      SyntaxTypes::GlobalVariableOrWriteNode
    ].freeze

    CONST_WRITE_NODES = [SyntaxTypes::ConstantWriteNode, SyntaxTypes::ConstantPathWriteNode].freeze

    CACHE_READS = [
      SyntaxTypes::InstanceVariableReadNode,
      SyntaxTypes::ClassVariableReadNode,
      SyntaxTypes::GlobalVariableReadNode,
      *OR_WRITE_NODES
    ].freeze

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

    HOLE_NODES = [SyntaxTypes::DefNode, SyntaxTypes::LambdaNode].freeze

    def initialize(source)
      @source = source
    end

    def ranges
      result = Kimera::Syntax.parse(@source)
      return [] if result.failure?
      visit(result.value)
    end

    private

    def visit(node)
      return [] unless node.is_a?(SyntaxTypes::Node)
      taint = taint(node)
      (taint ? [taint] : []) + node.compact_child_nodes.flat_map { |child| visit(child) }
    end

    def taint(node)
      case node
      when *OR_WRITE_NODES then value(node, "memoized via ||=")
      when *CONST_WRITE_NODES then value(node, "constant assignment (computed once)")
      when SyntaxTypes::IndexOrWriteNode then keyed(node)
      else cached(node)
      end
    end

    def value(node, reason)
      expression = node.value
      range(expression, reason) if expression
    end

    def keyed(node)
      value(node, "memoized via `cache[key] ||=`") if CACHE_READS.include?(bare(node.receiver).class)
    end

    def bare(node)
      inner = node.body&.body if node.is_a?(SyntaxTypes::ParenthesesNode)
      inner&.size == 1 ? inner.first : node
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

    def holes(node)
      return [] unless node.is_a?(SyntaxTypes::Node)
      hole = HOLE_NODES.any? { |kind| node.is_a?(kind) } ? node : Kimera::Deferral.new(node).block
      return body(hole) if hole
      node.compact_child_nodes.flat_map { |child| holes(child) }
    end

    def body(node)
      value = node.body
      value ? [span(value)] : []
    end

    def span(node)
      location = node.location
      start = location.start_offset
      [start, start + location.length]
    end
  end
end
