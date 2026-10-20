# frozen_string_literal: true

require "prism"
require_relative "../support/syntax"
require_relative "guardrail_factories"

module Kimera
  class BodyTrim
    VISIBILITY = %i[private protected public module_function private_class_method public_class_method].freeze
    RERUN = %i[require require_relative ruby2_keywords].freeze
    CONDITIONS = [Prism::IfNode, Prism::UnlessNode].freeze
    DECLARATIONS = %i[included prepended class_methods concerning class_eval module_eval class_exec module_exec].freeze
    FACTORIES = Kimera::GuardrailFactories::FACTORIES
    LOCALS = [
      Prism::LocalVariableWriteNode, Prism::LocalVariableOperatorWriteNode,
      Prism::LocalVariableOrWriteNode, Prism::LocalVariableAndWriteNode
    ].freeze
    STRINGS = [Prism::StringNode, Prism::InterpolatedStringNode, Prism::XStringNode, Prism::InterpolatedXStringNode].freeze

    def initialize(source, locations)
      @source = source
      @locations = locations
    end

    def trim(path) = loaded?(path) ? trimmed : @source

    def trimmed
      text = blank(dead(Kimera::Syntax.parse(@source).value.statements))
      Kimera::Syntax.parse(text).success? ? text : @source
    end

    private

    def loaded?(path)
      features = $LOADED_FEATURES
      features.include?(path) || features.include?(File.realpath(path))
    rescue SystemCallError
      false
    end

    def dead(statements)
      defined = []
      statements.body.flat_map do |node|
        next [node] unless live?(node) || kept?(unguarded(node), defined)
        defined << node.name if node.is_a?(Prism::DefNode)
        Array(inner(node)).grep(Prism::StatementsNode).flat_map { |body| dead(body) }
      end
    end

    def live?(node)
      location = node.location
      from = location.start_offset
      to = location.end_offset
      @locations.any? { |live| live.inside?(from, to) }
    end

    def kept?(node, defined)
      case node
      when Prism::CallNode then directive?(node, defined)
      when Prism::AliasMethodNode then defined.include?(named(node.old_name))
      else local?(node)
      end
    end

    def unguarded(node) = CONDITIONS.include?(node.class) && modifier?(node) ? node.statements.body.first : node

    def modifier?(node) = node.location.end_offset == node.predicate.location.end_offset

    def local?(node)
      return [*node.lefts, *node.rights].any?(Prism::LocalVariableTargetNode) if node.is_a?(Prism::MultiWriteNode)
      LOCALS.any? { |kind| node.is_a?(kind) }
    end

    def directive?(call, defined)
      name = call.name
      arguments = call.arguments&.arguments || []
      return arguments.none?(Prism::DefNode) if VISIBILITY.include?(name)
      RERUN.include?(name) || (name == :alias_method && defined.include?(named(arguments[1])))
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
      when *CONDITIONS then branches(node)
      end
    end

    def branches(node) = [node.statements, *otherwise(following(node))]

    def otherwise(tail)
      case tail
      when Prism::IfNode then branches(tail)
      when Prism::ElseNode then [tail.statements]
      else []
      end
    end

    def following(node)
      return node.else_clause if node.is_a?(Prism::UnlessNode)
      node.respond_to?(:subsequent) ? node.subsequent : node.consequent
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

    def blank(nodes)
      text = @source.b
      nodes.flat_map { |node| extents(node) }.each do |from, to|
        text[from...to] = text[from...to].tr("^\n", " ")
      end
      text.force_encoding(@source.encoding)
    end

    def extents(node)
      location = node.location
      [[location.start_offset, location.end_offset], *heredocs(node).map { |doc| body(doc) }]
    end

    def body(heredoc)
      [@source.byteindex("\n", heredoc.opening_loc.end_offset) + 1, heredoc.closing_loc.end_offset]
    end

    def heredocs(node)
      (STRINGS.include?(node.class) && node.heredoc? ? [node] : []) +
        node.compact_child_nodes.flat_map { |child| heredocs(child) }
    end
  end
end
