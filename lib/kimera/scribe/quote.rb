# frozen_string_literal: true

module Kimera
  class Scribe
    class Quote
      NAMED = {
        "\n" => "\\n", "\t" => "\\t", "\r" => "\\r", "\e" => "\\e", "\a" => "\\a", "\b" => "\\b", "\f" => "\\f",
        "\v" => "\\v", "\\" => "\\\\"
      }.freeze
      SIGILS = ["{", "$", "@"].freeze

      def initialize(value, delimiter = '"')
        @value = value
        @delimiter = delimiter
      end

      def text
        chars = @value.chars
        chars.each_with_index.sum("") { |char, index| escaped(char, chars[index + 1]) }
      end

      private

      def escaped(char, following)
        return NAMED.fetch(char) if NAMED.key?(char)
        return "\\#{char}" if @delimiter.include?(char) || (char == "#" && SIGILS.include?(following))
        literal?(char) ? char : coded(char)
      end

      def literal?(char) = char.ascii_only? && char.ord.between?(0x20, 0x7E)

      def coded(char)
        return format("\\x%02X", char.ord) if char.ascii_only?
        return format("\\u{%X}", char.ord) if char.valid_encoding? && @value.valid_encoding? && @value.encoding == Encoding::UTF_8
        char.bytes.sum("") { |byte| format("\\x%02X", byte) }
      end
    end

    class Unescaped
      FORCED = { forced_utf8_encoding?: Encoding::UTF_8, forced_binary_encoding?: Encoding::BINARY }.freeze

      def initialize(node)
        @node = node
      end

      def text
        value = @node.unescaped
        forced = FORCED.find { |flag, _| @node.public_send(flag) }&.last
        forced ? value.dup.force_encoding(forced) : value
      end
    end
  end
end
