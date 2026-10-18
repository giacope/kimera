# frozen_string_literal: true

module Kimera
  class Warnings
    def initialize(level)
      @level = level
    end

    def during
      previous = $VERBOSE
      $VERBOSE = @level
      yield
    ensure
      $VERBOSE = previous
    end

    SILENCED = new(nil)
  end
end
