# frozen_string_literal: true

module Kimera
  class Scribe
    class Shape
      ASSIGNING = %i[lvasgn ivasgn gvasgn cvasgn casgn op_asgn or_asgn and_asgn indexasgn].freeze
      SPREAD = %i[splat block_pass kwargs forwarded_args forwarded_restarg forwarded_kwrestarg].freeze
      SETTER = /\A[A-Za-z_].*=\z/

      def initialize(node)
        @node = node
      end

      def assignment? = ASSIGNING.include?(@node.type) || setter?

      def setter? = call? && @node.children[1].match?(SETTER) && single?

      def single?
        arguments = @node.children.drop(2)
        arguments.one? && !SPREAD.include?(arguments.first.type)
      end

      def prefix? = @node.type == :send && Level::PREFIX.key?(@node.children[1]) && @node.children.size == 2

      def numeral? = Numeral::TYPES.include?(@node.type)

      def spelled?(word)
        keyword = Hash(@node.location&.to_hash).values_at(:selector, :operator).compact.first
        keyword ? keyword.source == word : false
      end

      private

      def call? = %i[send csend].include?(@node.type)
    end
  end
end
