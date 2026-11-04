# frozen_string_literal: true

require_relative "operands"

module Kimera
  class Scribe
    class Shape
      WRITES = /_(?:operator_|or_|and_)?write_node\z/
      SPREAD = %i[splat_node keyword_hash_node forwarding_arguments_node block_argument_node].freeze

      def initialize(node)
        @node = node
      end

      def assignment? = (@node.type.match?(WRITES) && @node.type != :multi_write_node) || setter?

      def setter? = call? && @node.attribute_write? && !@node.name.end_with?("]=")

      def prefix? = operator?(PREFIX) && arguments.empty?

      def binary? = operator?(BINARY) && single?

      private

      def call? = @node.type == :call_node

      def operator?(table) = call? && table.key?(@node.name) && @node.receiver && plain?

      def plain? = !@node.safe_navigation? && @node.block.nil?

      def arguments = Operands.new(@node).to_a

      def single? = arguments.one? && !SPREAD.include?(arguments.first.type)
    end
  end
end
