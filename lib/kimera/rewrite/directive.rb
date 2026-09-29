# frozen_string_literal: true

require_relative "../support/operator_protocol"
require_relative "../support/unparse"

require_relative "directive_handlers"
require_relative "numbered_params"

module Kimera
  module Rewrite
    TYPE = OperatorProtocol::TYPE
    INDEX = OperatorProtocol::INDEX
    STATEMENT_DELETION = OperatorProtocol::STATEMENT_DELETION

    module Directive
      module_function

      def render(source, directive)
        shortcut(directive) || attempt(source, directive)
      end

      def shortcut(directive)
        type = directive[TYPE]
        return "(statement deleted)" if type == STATEMENT_DELETION
        return String(directive["value"]).inspect if type == "string_literal"
        "#{directive["name"]} (default removed)" if type == "required_argument"
      end

      def attempt(source, directive)
        Kimera::Unparse.unparse(apply(NumberedParams.normalize(Kimera::Unparse.parse(source)), directive))
      rescue StandardError
        nil
      end

      def table(*entries) = entries.each_slice(2).to_h.freeze

      VALUE_HANDLERS = table(
        "comparison", :swap, "op_swap", :swap, "selector_swap", :select,
        "op_asgn_swap", :assign, "csend_to_send", :send, "index_to_fetch", :fetch,
        "boolean_literal", :literal, "integer_literal", :integer, "float_literal", :float,
        "string_literal", :string, "symbol_literal", :symbol, "regexp_literal", :regexp,
        "boolean_connective", :connective, "range_flip", :retype, "condition", :retest
      )
      STRUCTURAL_HANDLERS = table(
        STATEMENT_DELETION, :clear, "return_nil", :nothing, "empty_collection", :empty,
        "unwrap_receiver", :receiver, "drop_receiver_link", :unlink, "drop_element", :remove,
        "drop_argument", :drop, "unwrap_argument", :argument, "required_argument", :default,
        "kwarg_element_drop", :keyword, "kwarg_pair_drop", :option
      )
      HANDLERS = VALUE_HANDLERS.merge(STRUCTURAL_HANDLERS).freeze

      def apply(node, directive)
        DirectiveHandlers::Operation.new(node, directive).public_send(handler(directive))
      end

      def handler(directive)
        HANDLERS.fetch(directive[TYPE]) { raise(ArgumentError, "unknown directive #{directive.inspect}") }
      end
    end
  end
end
