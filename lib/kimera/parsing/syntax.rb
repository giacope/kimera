# frozen_string_literal: true

require "prism"
require_relative "branches"

module Kimera
  module Syntax
    %i[
      AndNode ArrayNode AssocNode AssocSplatNode BeginNode BlockArgumentNode BlockNode BlockParametersNode
      BreakNode ClassNode ForwardingSuperNode LocalVariableTargetNode LocalVariableWriteNode ModuleNode
      NextNode ProgramNode RescueModifierNode SingletonClassNode SuperNode
      CallNode ClassVariableOrWriteNode ClassVariableReadNode ClassVariableWriteNode
      CallOperatorWriteNode ClassVariableOperatorWriteNode ConstantOperatorWriteNode
      ConstantPathOperatorWriteNode GlobalVariableOperatorWriteNode
      InstanceVariableOperatorWriteNode LocalVariableOperatorWriteNode
      ConstantPathWriteNode ConstantReadNode ConstantWriteNode DefNode DefinedNode EmbeddedStatementsNode
      FalseNode FloatNode IndexOrWriteNode
      ForwardingArgumentsNode GlobalVariableOrWriteNode GlobalVariableReadNode
      GlobalVariableWriteNode HashNode IfNode InNode InstanceVariableOrWriteNode
      InstanceVariableReadNode InstanceVariableWriteNode IntegerNode KeywordHashNode
      LambdaNode LocalVariableReadNode MatchPredicateNode MatchRequiredNode NilNode Node
      OptionalKeywordParameterNode OptionalParameterNode OrNode ParametersNode ParenthesesNode
      RangeNode RegularExpressionNode ReturnNode SplatNode StatementsNode StringNode
      SymbolNode TrueNode UnlessNode
    ].each { |name| const_set(name, Prism.const_get(name)) }

    CallNodeFlags = Prism::CallNodeFlags
    RangeFlags = Prism::RangeFlags

    OPERATOR_WRITES = [
      CallOperatorWriteNode, ClassVariableOperatorWriteNode, ConstantOperatorWriteNode,
      ConstantPathOperatorWriteNode, GlobalVariableOperatorWriteNode,
      InstanceVariableOperatorWriteNode, LocalVariableOperatorWriteNode
    ].freeze

    View =
      Data.define(:node) do
        def collection(splats)
          [node.elements, splats[node.class]] if splats.key?(node.class)
        end

        def unwrap(names)
          return unless node.is_a?(CallNode) && node.receiver && names.include?(node.name)
          node.name unless node.arguments || node.block
        end

        def operator
          node.binary_operator if OPERATOR_WRITES.any? { |kind| node.is_a?(kind) }
        end

        def diagnostic?(names, loggers)
          receiver = node.receiver
          return names.include?(node.name) unless receiver
          logger?(receiver, loggers)
        end
        private
        def logger?(receiver, loggers)
          while receiver
            return true if named?(receiver, loggers)
            receiver = receiver.is_a?(CallNode) ? receiver.receiver : nil
          end
          false
        end

        def named?(receiver, names)
          receiver.class.method_defined?(:name) && names.include?(receiver.name)
        end
      end

    def self.parse(source, **) = Prism.parse(source, **)

    # The scope a directive's snippet parses in: a method body that may forward
    # its arguments (`*`, `**`, `&`, `...`).
    FORWARDING = Prism.scope(forwarding: %i[* ** & ...])

    BRANCHES = ->(conditional) { Kimera::Branches.new(conditional).bodies }

    # A rescue clause and every one after it.
    RESCUES = ->(clause) { clause ? [clause, *RESCUES.call(clause.subsequent)] : [] }
  end
end
