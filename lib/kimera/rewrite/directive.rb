# frozen_string_literal: true

require_relative "../parsing/syntax"
require_relative "../support/operator_protocol"
require_relative "../unparsing/unparse"

require_relative "clause_handlers"
require_relative "directive_handlers"
require_relative "numbered_params"

module Kimera
  module Rewrite
    TYPE = OperatorProtocol::TYPE
    INDEX = OperatorProtocol::INDEX
    STATEMENT_DELETION = OperatorProtocol::STATEMENT_DELETION

    class Directive
      TABLE = ->(*entries) { entries.each_slice(2).to_h.freeze }

      VALUE_HANDLERS = TABLE.call(
        "comparison", :swap, "op_swap", :swap, "selector_swap", :select,
        "op_asgn_swap", :assign, "csend_to_send", :send, "index_to_fetch", :fetch,
        "boolean_literal", :literal, "integer_literal", :integer, "float_literal", :float,
        "string_literal", :string, "symbol_literal", :symbol, "regexp_literal", :regexp,
        "boolean_connective", :retype, "range_flip", :retype, "condition", :retest
      )
      STRUCTURAL_HANDLERS = TABLE.call(
        STATEMENT_DELETION, :clear, "return_nil", :nothing, "empty_collection", :empty,
        "unwrap_receiver", :receiver, "drop_receiver_link", :unlink, "drop_element", :remove,
        "drop_argument", :drop, "unwrap_argument", :argument, "required_argument", :default,
        "kwarg_element_drop", :keyword, "kwarg_pair_drop", :option
      )
      HANDLERS = VALUE_HANDLERS.merge(STRUCTURAL_HANDLERS).freeze
      BINDINGS = [Prism::LocalVariableWriteNode, Prism::MatchWriteNode].freeze
      CLAUSE_HANDLERS = TABLE.call(
        "drop_rescue", :rescued, "drop_ensure", :ensured, "privatize", :privatize,
        "assigned_value", :value, "nil_object", :object, "regexp_source", :pattern
      )

      def initialize(directive)
        @directive = directive
      end

      def render(source)
        shortcut || forced(source, condition) || attempt(source)
      end

      def apply(node)
        operation(node).public_send(handler)
      end

      private

      def condition
        @directive["to"] if @directive[TYPE] == "condition"
      end

      def forced(source, value)
        tree = Kimera::Syntax.parse(source, scopes: [Kimera::Syntax::FORWARDING])
        pinned(source, tree.value.statements.body.first.predicate, value) if value && tree.success?
      rescue NoMethodError
        nil
      end

      def pinned(source, predicate, value)
        splice(source, predicate.location, binds?(predicate) ? "(#{predicate.slice}; #{value})" : value)
      end

      def binds?(node)
        BINDINGS.any? { |type| node.is_a?(type) } || node.compact_child_nodes.any? { |child| binds?(child) }
      end

      def splice(source, span, text)
        source.byteslice(0, span.start_offset) + text + source.byteslice(span.end_offset..)
      end

      def shortcut
        type = @directive[TYPE]
        return "(statement deleted)" if type == STATEMENT_DELETION
        return String(@directive["value"]).inspect if type == "string_literal"
        "#{@directive["name"]} (default removed)" if type == "required_argument"
      end

      def attempt(source)
        Kimera::Unparse.new(apply(NumberedParams.new(Kimera::Unparse.parse(source)).normalize)).source
      rescue StandardError
        nil
      end

      def operation(node)
        (CLAUSE_HANDLERS.key?(@directive[TYPE]) ? ClauseHandlers : DirectiveHandlers)::Operation.new(node, @directive)
      end

      def handler
        type = @directive[TYPE]
        HANDLERS.fetch(type) do
          CLAUSE_HANDLERS.fetch(type) do
            raise(ArgumentError, "unknown directive #{@directive.inspect}")
          end
        end
      end
    end
  end
end
