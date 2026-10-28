# frozen_string_literal: true

module Kimera
  class Scribe
    class Sequence < Form
      TYPES = %i[statements_node].freeze

      def text = @node.body.map { |statement| pen_of(statement).opened.write(statement) }.join("; ")

      def level
        body = @node.body
        body.one? ? pen_of(body.first).level(body.first) : Level::STATEMENT
      end
    end

    class Parentheses < Form
      TYPES = %i[parentheses_node].freeze

      def text
        body = @node.body
        return "()" unless body
        "(#{part(body)})"
      end
    end

    class Elements < Form
      TYPES = %i[array_node].freeze

      def text
        listed = "[#{listed(@node.elements)}]"
        @pen.pattern? ? Words.new(@node, @pen).text || "^(#{listed})" : listed
      end
    end

    class Words
      SIGILS = {
        string_node: "W", interpolated_string_node: "W", symbol_node: "I", interpolated_symbol_node: "I"
      }.freeze
      BREAKS = "[] "

      def initialize(node, pen)
        @node = node
        @pen = pen
      end

      def text
        words = @node.elements.map { |element| word(element) }
        "%#{sigils.first || "w"}[#{words.join(" ")}]" if sigils.size < 2 && words.all?
      end

      private

      def sigils = @node.elements.map { |element| SIGILS[element.type] }.uniq

      def word(element)
        return unless SIGILS.key?(element.type)
        return @pen.form(element).word if element.respond_to?(:parts)
        text = element.unescaped
        Quote.new(text, BREAKS).text unless text.empty?
      end
    end

    class Arguments < Form
      TYPES = %i[arguments_node keyword_hash_node].freeze

      def text = listed(type == :arguments_node ? @node.arguments : @node.elements)
    end

    class Pairs < Form
      TYPES = %i[hash_node].freeze

      def text = @node.elements.empty? ? "{}" : "{ #{listed(@node.elements)} }"
    end

    class Pair < Form
      TYPES = %i[assoc_node].freeze

      def text
        key = @node.key
        return "#{Name.new(key.unescaped.to_sym).label}#{" #{value}" unless shorthand?}" if key.type == :symbol_node
        return "#{part(key).delete_prefix(":")}: #{value}" if key.type == :interpolated_symbol_node
        "#{leading(key, Level::RANGE)} => #{value}"
      end

      private

      def value = part(@node.value, Level::ASSIGNMENT)

      def shorthand? = @node.value.nil? || @node.value.type == :implicit_node
    end

    class Splat < Form
      TYPES = %i[splat_node assoc_splat_node block_argument_node].freeze
      PREFIXES = { splat_node: "*", assoc_splat_node: "**", block_argument_node: "&" }.freeze

      def text
        inner = type == :assoc_splat_node ? @node.value : @node.expression
        "#{PREFIXES.fetch(type)}#{part(inner, Level::ASSIGNMENT) if inner}"
      end
    end

    class Span < Form
      TYPES = %i[range_node flip_flop_node].freeze

      def text
        first = @node.left
        last = @node.right
        floor = Level::RANGE + 1
        "#{leading(first, floor) if first}#{@node.exclude_end? ? "..." : ".."}#{trailing(last, floor) if last}"
      end

      def level = Level::RANGE
    end
  end
end
