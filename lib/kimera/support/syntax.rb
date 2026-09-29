# frozen_string_literal: true

require "prism"

module Kimera
  module Syntax
    %i[
      AndNode ArrayNode AssocNode AssocSplatNode BlockArgumentNode BlockNode BlockParametersNode
      CallNode ClassVariableOrWriteNode ClassVariableReadNode ClassVariableWriteNode
      CallOperatorWriteNode ClassVariableOperatorWriteNode ConstantOperatorWriteNode
      ConstantPathOperatorWriteNode GlobalVariableOperatorWriteNode
      InstanceVariableOperatorWriteNode LocalVariableOperatorWriteNode
      ConstantPathWriteNode ConstantWriteNode DefNode DefinedNode FalseNode FloatNode
      ForwardingArgumentsNode GlobalVariableOrWriteNode GlobalVariableReadNode
      GlobalVariableWriteNode HashNode IfNode InNode InstanceVariableOrWriteNode
      ImaginaryNode InstanceVariableReadNode InstanceVariableWriteNode IntegerNode KeywordHashNode
      LambdaNode LocalVariableReadNode MatchPredicateNode MatchRequiredNode NilNode Node
      OptionalKeywordParameterNode OptionalParameterNode OrNode ParametersNode ParenthesesNode
      RangeNode RationalNode RegularExpressionNode ReturnNode SplatNode StatementsNode StringNode
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

    module Shape
      NUMERIC = [IntegerNode, FloatNode, RationalNode, ImaginaryNode].freeze
      POSITIONAL = %i[node_id location].freeze
      PLACEMENT_FLAGS = Prism::NodeFlags::NEWLINE | Prism::NodeFlags::STATIC_LITERAL

      module_function

      def of(node)
        number = value(node)
        return [Numeric, number.inspect] if number
        inner = lone(node)
        inner ? of(inner) : [node.class, flags(node), fields(node)]
      end

      def value(node)
        inner = lone(node)
        return value(inner) if inner
        return node.value if NUMERIC.include?(node.class)
        number = negation?(node) && value(node.receiver)
        -number if number
      end

      def lone(node)
        return unless node.is_a?(ParenthesesNode)
        body = node.body
        return unless body.is_a?(StatementsNode)
        statements = body.body
        statements.first if statements.one?
      end

      def negation?(node)
        node.is_a?(CallNode) && node.name == :-@ && !node.arguments && !node.block
      end

      def flags(node) = node.__send__(:flags) & ~PLACEMENT_FLAGS

      def fields(node)
        node.deconstruct_keys(nil).except(*POSITIONAL).transform_values { field(it) }
      end

      def field(value) = value.is_a?(Array) ? value.map { field(it) } : scalar(value)

      def scalar(value)
        case value
        when Prism::Node then of(value)
        when Prism::Location then value.class
        else value
        end
      end
    end

    module_function

    def parse(source) = Prism.parse(source)
    def view(node) = View.new(node)
    def shape(node) = Shape.of(node)
  end
end
