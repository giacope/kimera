# frozen_string_literal: true

module Kimera
  class Scribe
    class Operands
      def initialize(node)
        @node = node
      end

      def to_a = @node.arguments&.arguments || []
    end
  end
end
