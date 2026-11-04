# frozen_string_literal: true

# A clock that reads the times it was given, one per look, and counts its
# pauses instead of pausing.
class FakeClock
  attr_reader :paused

  def initialize(*readings)
    @readings = readings
    @paused = 0
  end

  def now = @readings.shift

  def pause = (@paused += 1)
end
