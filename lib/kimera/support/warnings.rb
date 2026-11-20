# frozen_string_literal: true

module Kimera
  class Warnings
    def self.silenced = new

    def during
      previous = $VERBOSE
      $VERBOSE = nil
      yield
    ensure
      $VERBOSE = previous
    end
  end
end
