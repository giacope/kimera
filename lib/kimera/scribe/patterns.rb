# frozen_string_literal: true

module Kimera
  class Scribe
    class Matching < Form
      TYPES = %i[match_pattern match_pattern_p].freeze

      def text = "#{leading(0, Level::KEYWORD + 1)} #{type == :match_pattern ? "=>" : "in"} #{part(1)}"

      def level = Level::EXPRESSION
    end

    class Alternatives < Form
      TYPES = %i[match_alt match_as].freeze

      def text = "#{part(0, 1)} #{type == :match_alt ? "|" : "=>"} #{part(1, 2)}"

      def level = type == :match_alt ? 1 : 0
    end

    class ArrayPattern < Form
      TYPES = %i[array_pattern array_pattern_with_tail find_pattern].freeze

      def text = "[#{items}]"

      def items = "#{rest(0, Level::STATEMENT)}#{"," if type == :array_pattern_with_tail}"
    end

    class HashPattern < Form
      TYPES = %i[hash_pattern].freeze

      def text = children.empty? ? "{}" : "{ #{items} }"

      def items = children.zip(pens).each_with_index.map { |_, index| entry(index) }.join(", ")

      private

      def entry(index)
        child = children.fetch(index)
        key, value = child.children
        case child.type
        when :match_var then "#{key}:"
        when :match_rest then "**#{key&.children&.first}"
        when :pair then "#{Name.new(key.children.first).label} #{pens.fetch(index).write(value)}"
        else part(index)
        end
      end
    end

    class ConstPattern < Form
      TYPES = %i[const_pattern].freeze

      def text
        pattern = children[1]
        inner = (pattern.type == :hash_pattern ? HashPattern : ArrayPattern).new(pattern, pens[1]).items
        "#{part(0, Level::PRIMARY)}(#{inner})"
      end
    end

    class Rest < Form
      TYPES = %i[match_rest].freeze

      def text = "*#{part(0) if children.first}"
    end

    class Pin < Form
      TYPES = %i[pin].freeze

      def text = "^#{part(0, Level::PRIMARY)}"
    end
  end
end
