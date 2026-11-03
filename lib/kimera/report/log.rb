# frozen_string_literal: true

require_relative "surface"

class Kimera::Report::Log < Kimera::Report::Surface
  HEARTBEAT_EVERY = 30.0

  def cadence = HEARTBEAT_EVERY

  def painted(frame, tally, now)
    line = tally.plain(now)
    [frame.over(line, now), ["#{line}\n"]]
  end

  private

  def commit(frame) = wipe(frame)

  def wipe(_frame) = ""
end
