# frozen_string_literal: true

module Kimera
  class Warnings
    def self.silenced = new(nil)

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
  end
end
