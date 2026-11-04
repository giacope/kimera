# frozen_string_literal: true

module Kimera
  class Scribe
    class Mode
      def initialize(open:, pattern:)
        @open = open
        @pattern = pattern
      end

      def open? = @open

      def pattern? = @pattern

      def patterned = Mode.new(open: @open, pattern: true)
    end
    OPEN = Mode.new(open: true, pattern: false)
    CLOSED = Mode.new(open: false, pattern: false)
    private_constant(:OPEN, :CLOSED)
  end
end
