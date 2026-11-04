# frozen_string_literal: true

require_relative "../parsing/syntax"
require_relative "../scribe"

require_relative "clause_handlers"
require_relative "directive_handlers"
require_relative "numbered_params"

module Kimera
  module Rewrite
    TYPE = "type"
    INDEX = "index"
    STATEMENT_DELETION = "statement_deletion"
    private_constant(:TYPE, :INDEX, :STATEMENT_DELETION)

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
        "assigned_value", :value, "nil_object", :object, "regexp_source", :pattern, "drop_when", :unbranched
      )

      def initialize(directive)
        @directive = directive
      end

      def render(source)
        [-> { shortcuts }, -> { forced(source) { [] } }, -> { attempt(source) { [] } }].lazy.flat_map(&:call).first(1)
      end

      def apply(node)
        operation(node).call(handler)
      end

      def kind?(name) = @directive[TYPE] == name

      def position = Integer(@directive[INDEX])

      private

      def parsed(source) = Kimera::Syntax::Fragment.new(source).tree

      def forced(source)
        value = @directive["to"]
        return [] unless kind?("condition") && value
        tree = parsed(source)
        tree.success? ? [pinned(source, tree.value.statements.body.first.predicate, value)] : []
      rescue NoMethodError
        yield
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

      def shortcuts
        type = @directive[TYPE]
        return ["(statement deleted)"] if type == STATEMENT_DELETION
        return [String(@directive["value"]).inspect] if type == "string_literal"
        type == "required_argument" ? ["#{@directive["name"]} (default removed)"] : []
      end

      def attempt(source)
        tree = parsed(source)
        return [] unless tree.success?
        program = NumberedParams.new(tree.value).normalize
        node = program.statements.body.first
        [Kimera::Scribe.new(apply(node)).at(program, node).source]
      rescue StandardError
        yield
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
