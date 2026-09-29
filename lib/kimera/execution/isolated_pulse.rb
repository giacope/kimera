# frozen_string_literal: true

module Kimera
  module Execution
  end
end

class Kimera::Execution::IsolatedPulse
  CLOCK = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
  Mark = Data.define(:beats, :deadline)
  UNSEEN = Mark.new(beats: -1, deadline: 0.0)

  def initialize(path, limit, clock: CLOCK)
    @path = path
    @limit = limit
    @clock = clock
    @mark = UNSEEN
  end

  def expired?
    @mark = observed(@mark)
    @clock.call >= @mark.deadline
  end

  private

  def observed(mark)
    beats = size
    beats > mark.beats ? Mark.new(beats: beats, deadline: @clock.call + @limit) : mark
  end

  def size
    File.size(@path)
  rescue SystemCallError
    0
  end
end
