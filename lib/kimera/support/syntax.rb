# frozen_string_literal: true

require "prism"

module Kimera
  module Syntax
    %i[
      AndNode ArrayNode AssocNode AssocSplatNode BlockArgumentNode BlockNode
      CallNode ClassVariableOrWriteNode ClassVariableReadNode ClassVariableWriteNode
      CallOperatorWriteNode ClassVariableOperatorWriteNode ConstantOperatorWriteNode
      ConstantPathOperatorWriteNode GlobalVariableOperatorWriteNode
      InstanceVariableOperatorWriteNode LocalVariableOperatorWriteNode
      ConstantPathWriteNode ConstantWriteNode DefNode DefinedNode FalseNode FloatNode
      ForwardingArgumentsNode GlobalVariableOrWriteNode GlobalVariableReadNode
      GlobalVariableWriteNode HashNode IfNode InNode InstanceVariableOrWriteNode
      InstanceVariableReadNode InstanceVariableWriteNode IntegerNode KeywordHashNode
      LambdaNode MatchPredicateNode MatchRequiredNode NilNode Node
      OptionalKeywordParameterNode OptionalParameterNode OrNode ParenthesesNode
      RangeNode RegularExpressionNode ReturnNode SplatNode StatementsNode StringNode
      SymbolNode TrueNode UnlessNode
    ].each { |name| const_set(name, Prism.const_get(name)) }

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

    module_function

    def parse(source) = Prism.parse(source)
    def view(node) = View.new(node)
  end
end
