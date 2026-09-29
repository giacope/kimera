# frozen_string_literal: true

require "prism"
require_relative "../support/syntax"
require_relative "guardrail_value_objects"

module Kimera
  module BodyTrim
    module_function

    VISIBILITY = %i[private protected public module_function private_class_method public_class_method].freeze
    LOADS = %i[require require_relative].freeze
    DECLARATIONS = %i[included prepended class_methods concerning class_eval module_eval class_exec module_exec].freeze
    FACTORIES = Kimera::GuardrailValueObjects::FACTORIES
    LOCALS = [
      Prism::LocalVariableWriteNode, Prism::LocalVariableOperatorWriteNode,
      Prism::LocalVariableOrWriteNode, Prism::LocalVariableAndWriteNode
    ].freeze
    STRINGS = [Prism::StringNode, Prism::InterpolatedStringNode, Prism::XStringNode, Prism::InterpolatedXStringNode].freeze

    def trim(path, source, locations) = loaded?(path) ? trimmed(source, locations) : source

    def loaded?(path)
      features = $LOADED_FEATURES
      features.include?(path) || features.include?(File.realpath(path))
    rescue SystemCallError
      false
    end

    def trimmed(source, locations)
      text = blank(source, dead(Kimera::Syntax.parse(source).value.statements, locations))
      Kimera::Syntax.parse(text).success? ? text : source
    end

    def dead(statements, locations, found = [])
      defined = []
      statements.body.each { |node| sort(node, locations, found, defined) }
      found
    end

    def sort(node, locations, found, defined)
      return found << node unless live?(node, locations) || kept?(node, defined)
      defined << node.name if node.is_a?(Prism::DefNode)
      body = inner(node)
      dead(body, locations, found) if body.is_a?(Prism::StatementsNode)
    end

    def live?(node, locations)
      location = node.location
      from = location.start_offset
      to = location.end_offset
      locations.any? { |live| live.within?(from, to) }
    end

    def kept?(node, defined)
      case node
      when Prism::CallNode then directive?(node, defined)
      when Prism::AliasMethodNode then defined.include?(named(node.old_name))
      else local?(node)
      end
    end

    def local?(node)
      return [*node.lefts, *node.rights].any?(Prism::LocalVariableTargetNode) if node.is_a?(Prism::MultiWriteNode)
      LOCALS.any? { |kind| node.is_a?(kind) }
    end

    def directive?(call, defined)
      name = call.name
      arguments = call.arguments&.arguments || []
      return arguments.none?(Prism::DefNode) if VISIBILITY.include?(name)
      LOADS.include?(name) || (name == :alias_method && defined.include?(named(arguments[1])))
    end

    def named(node)
      case node
      when Prism::SymbolNode, Prism::StringNode then node.unescaped.to_sym
      end
    end

    def inner(node)
      case node
      when Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode then node.body
      when Prism::CallNode then declared(node)
      when Prism::ConstantWriteNode, Prism::ConstantPathWriteNode then declared(node.value)
      end
    end

    def declared(node)
      block = node.block if node.is_a?(Prism::CallNode)
      block.body if block.is_a?(Prism::BlockNode) && declaration?(node)
    end

    def declaration?(call)
      name = call.name
      DECLARATIONS.include?(name) || factory?(call.receiver, name)
    end

    def factory?(receiver, name) = receiver.is_a?(Prism::ConstantReadNode) && FACTORIES.include?([receiver.name, name])

    def blank(source, nodes)
      text = source.b
      nodes.flat_map { |node| extents(source, node) }.each do |from, to|
        text[from...to] = text[from...to].tr("^\n", " ")
      end
      text.force_encoding(source.encoding)
    end

    def extents(source, node)
      location = node.location
      [[location.start_offset, location.end_offset], *heredocs(node).map { |doc| body(source, doc) }]
    end

    def body(source, heredoc)
      [source.byteindex("\n", heredoc.opening_loc.end_offset) + 1, heredoc.closing_loc.end_offset]
    end

    def heredocs(node, found = [])
      found << node if STRINGS.include?(node.class) && node.heredoc?
      node.compact_child_nodes.each { |child| heredocs(child, found) }
      found
    end
  end
end
