# frozen_string_literal: true

module Kimera
  module Execution
  end
end

class Kimera::Execution::IsolatedPulse
  CLOCK = ->(reading = Process.clock_gettime(Process::CLOCK_MONOTONIC)) { reading }
  Mark = Data.define(:beats, :deadline)
  UNSEEN = Mark.new(beats: -1, deadline: 0.0)

  def initialize(path, limit, clock: CLOCK, mark: UNSEEN)
    @path = path
    @limit = limit
    @clock = clock
    @mark = mark
  end

  def observed
    beats = size
    return self unless beats > @mark.beats
    self.class.new(@path, @limit, clock: @clock, mark: Mark.new(beats: beats, deadline: @clock.call + @limit))
  end

  def expired? = @clock.call >= @mark.deadline

  private

  def size
    File.size(@path)
  rescue SystemCallError
    0
  end
end
