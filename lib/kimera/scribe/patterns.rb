# frozen_string_literal: true

module Kimera
  class Scribe
    class Matching < Form
      TYPES = %i[match_predicate_node match_required_node].freeze

      def text
        "#{leading(
          @node.value,
          Level::KEYWORD + 1
        )} #{type == :match_required_node ? "=>" : "in"} #{patterned(@node.pattern)}"
      end

      def level = Level::EXPRESSION
    end

    class Alternatives < Form
      TYPES = %i[alternation_pattern_node capture_pattern_node].freeze

      def text
        return "#{part(@node.left, 1)} | #{part(@node.right, 2)}" if type == :alternation_pattern_node
        "#{part(@node.value, 1)} => #{part(@node.target, 2)}"
      end

      def level = type == :alternation_pattern_node ? 1 : 0
    end

    class ArrayPattern < Form
      TYPES = %i[array_pattern_node find_pattern_node].freeze

      def text
        constant = @node.constant
        constant ? "#{part(constant, Level::PRIMARY)}(#{items})" : "[#{items}]"
      end

      private

      def items
        trailed(type == :find_pattern_node ? [@node.left, *@node.requireds, @node.right] : elements)
      end

      def elements = [*@node.requireds, *@node.rest, *@node.posts]
    end

    class HashPattern < Form
      TYPES = %i[hash_pattern_node].freeze

      def text
        constant = @node.constant
        return "#{part(constant, Level::PRIMARY)}(#{items})" if constant
        items.empty? ? "{}" : "{ #{items} }"
      end

      private

      def items = [*@node.elements, *@node.rest].map { |item| part(item) }.join(", ")
    end

    class Pin < Form
      TYPES = %i[pinned_variable_node pinned_expression_node].freeze

      def text
        return "^#{part(@node.variable)}" if type == :pinned_variable_node
        expression = @node.expression
        "^(#{pen_of(expression).opened.write(expression)})"
      end
    end
  end
end
