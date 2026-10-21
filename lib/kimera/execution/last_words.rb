# frozen_string_literal: true

require_relative "fault"
require_relative "stack_dump"

using Kimera::Execution::Fault

class Kimera::Execution::LastWords
  HARNESS = Kimera::Execution::StackDump::HARNESS
  MAX_FRAMES = Kimera::Execution::StackDump::MAX_FRAMES
  UNTRAPPED = "nothing trapped %s: a test that signals its own process must trap the signal first, " \
    "or be left out with --exclude-test"

  def initialize(error)
    @error = error
  end

  def to_s = [@error.headline, *advice, *frames].join("\n")

  private

  def frames
    trace = Array(@error.backtrace)
    own = trace.take_while { |frame| !frame.start_with?(HARNESS) }
    (own.empty? ? trace : own).first(MAX_FRAMES).map { |frame| "  #{frame.delete_prefix("#{Dir.pwd}/")}" }
  end

  def advice = @error.is_a?(SignalException) ? [format(UNTRAPPED, @error.message)] : []
end
