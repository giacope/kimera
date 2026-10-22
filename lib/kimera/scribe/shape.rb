# frozen_string_literal: true

module Kimera
  class Scribe
    class Shape
      WRITES = /_(?:operator_|or_|and_)?write_node\z/
      NUMERALS = %i[integer_node float_node rational_node imaginary_node].freeze
      SPREAD = %i[splat_node keyword_hash_node forwarding_arguments_node block_argument_node].freeze

      def initialize(node)
        @node = node
      end

      def assignment? = (@node.type.match?(WRITES) && @node.type != :multi_write_node) || setter?

      def setter? = call? && @node.attribute_write? && !@node.name.end_with?("]=")

      def prefix? = call? && Level::PREFIX.key?(@node.name) && @node.receiver && plain? && arguments.empty?

      def binary? = call? && Level::BINARY.key?(@node.name) && @node.receiver && plain? && single?

      def numeral? = NUMERALS.include?(@node.type)

      def spelled?(word)
        return @node.message == word if call?
        @node.respond_to?(:operator_loc) && @node.operator_loc&.slice == word
      end

      def arguments = @node.arguments&.arguments || []

      private

      def call? = @node.type == :call_node

      def plain? = !@node.safe_navigation? && @node.block.nil?

      def single? = arguments.one? && !SPREAD.include?(arguments.first.type)
    end
  end
end
