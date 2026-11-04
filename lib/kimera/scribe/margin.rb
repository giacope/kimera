# frozen_string_literal: true

module Kimera
  class Scribe
    class Margin
      def initialize(depth:, flat:)
        @depth = depth
        @flat = flat
      end

      def deeper = Margin.new(depth: depth + 1, flat: flat)

      def flattened = Margin.new(depth: depth, flat: true)

      def newline = flat ? "; " : "\n#{INDENT * depth}"

      def gap = flat ? "" : "\n"

      private

      attr_reader :depth, :flat
    end
  end
end
