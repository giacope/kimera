# frozen_string_literal: true

module Kimera
  module Execution
  end
end

class Kimera::Execution::IsolatedPulse
  CLOCK = ->(reading = Process.clock_gettime(Process::CLOCK_MONOTONIC)) { reading }

  class Mark
    def initialize(beats:, deadline:)
      @beats = beats
      @deadline = deadline
    end

    def grown?(beats) = beats > @beats

    def passed?(now) = now >= @deadline
  end

  UNSEEN = Mark.new(beats: -1, deadline: 0.0)

  def initialize(path, limit, clock: CLOCK, mark: UNSEEN)
    @path = path
    @limit = limit
    @clock = clock
    @mark = mark
  end

  def observed
    beats = size
    return self unless @mark.grown?(beats)
    self.class.new(@path, @limit, clock: @clock, mark: Mark.new(beats: beats, deadline: @clock.call + @limit))
  end

  def expired? = @mark.passed?(@clock.call)

  private

  def size = File.size?(@path).to_i
end
