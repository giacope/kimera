# frozen_string_literal: true

module Kimera
  class Scribe
    class Token
      NUMERALS = %i[integer_node float_node rational_node imaginary_node].freeze

      def initialize(node)
        @node = node
      end

      def numeral? = NUMERALS.include?(@node.type)

      def spelled?(word)
        return @node.message == word if @node.type == :call_node
        @node.respond_to?(:operator_loc) && @node.operator_loc&.slice == word
      end
    end
  end
end
