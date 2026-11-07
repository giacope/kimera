# frozen_string_literal: true

class FakeClock
  attr_reader :paused

  def initialize(*readings)
    @readings = readings
    @paused = 0
  end

  def now = @readings.shift

  def pause = (@paused += 1)
end
