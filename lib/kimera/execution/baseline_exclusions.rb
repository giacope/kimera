# frozen_string_literal: true

require_relative "failure_listing"

class Kimera::Execution::BaselineExclusions
  LISTED = 5

  def initialize(failures, command = nil)
    @failures = failures
    @command = command
  end

  def to_s
    return if @failures.empty?
    [
      "kimera: #{@failures.size} test(s) fail in the baseline, in a plain run too, and were excluded: their " \
        "coverage is unknown, so a mutant only they would reach reads uncovered or survived this run:",
      *Kimera::Execution::FailureListing.new(@failures).lines,
      @command && "  plain run: #{@command}"
    ].compact.join("\n")
  end
end
