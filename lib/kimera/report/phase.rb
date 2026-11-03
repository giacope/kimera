# frozen_string_literal: true

require_relative "frame"
require_relative "tally"

module Kimera
  module Report
  end
end

class Kimera::Report::Phase
  def initialize(surface, tally, frame)
    @surface = surface
    @tally = tally
    @frame = frame
  end

  def painted(now) = drawn(@tally, now)

  def ticked(status, clock)
    counted = @tally.counted(status)
    return [self.class.new(@surface, counted, @frame), []] unless counted.complete? || @frame.due?(clock.call)
    drawn(counted, clock.call)
  end

  def finished = @tally.complete? ? @surface.committed(@frame) : @surface.cleared(@frame)

  private

  def drawn(tally, now)
    frame, ink = @surface.painted(@frame, tally, now)
    [self.class.new(@surface, tally, frame), ink]
  end
end
