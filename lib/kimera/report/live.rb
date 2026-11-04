# frozen_string_literal: true

require_relative "surface"
require "io/console"

class Kimera::Report::Live < Kimera::Report::Surface
  REDRAW_EVERY = 0.1
  ERASE = "\r\e[K"
  CURSOR_UP = "\e[1A"

  def initialize(columns: 0)
    super()
    @columns = columns
  end

  def cadence = REDRAW_EVERY

  def painted(frame, tally, now)
    line = tally.line(now)
    [frame.over(line, now), ["#{wipe(frame)}#{line}"]]
  end

  private

  def commit(_frame) = "\n"

  def wipe(frame)
    ERASE + ((CURSOR_UP + ERASE) * (frame.rows(@columns) - 1))
  end
end
