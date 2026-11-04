# frozen_string_literal: true

require_relative "fault"
require_relative "frames"

using Kimera::Execution::Fault

class Kimera::Execution::LastWords
  UNTRAPPED = "nothing trapped %s: a test that signals its own process must trap the signal first, " \
    "or be left out with --exclude-test"

  def initialize(error)
    @error = error
  end

  def to_s = [@error.headline, *advice, *frames].join("\n")

  private

  def frames
    trace = Array(@error.backtrace)
    own = Kimera::Execution::Frames.new(trace).own
    Kimera::Execution::Frames.new(own.empty? ? trace : own).lines
  end

  def advice = @error.is_a?(SignalException) ? [format(UNTRAPPED, @error.message)] : []
end
