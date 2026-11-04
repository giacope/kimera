# frozen_string_literal: true

module Kimera
  class Duration
    def initialize(seconds)
      @seconds = seconds
    end

    def clock = format("%d:%02d", seconds / 60, seconds % 60)

    def brief
      return format("%.1fs", seconds) if seconds >= 1
      format(seconds >= 0.01 ? "%.0fms" : "%.1fms", seconds * 1000)
    end

    private

    attr_reader :seconds
  end
end
