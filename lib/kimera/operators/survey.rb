# frozen_string_literal: true

require_relative "vocabulary"

module Kimera
  module Operators
    class Survey
      def initialize(root)
        @root = root
      end

      def include?(node) = found.include?(node)

      NONE = new(Kimera::Syntax.parse("").value)

      private

      def found = @_found ||= Set.new.compare_by_identity.merge(nodes)

      def nodes = []
    end
  end
end
