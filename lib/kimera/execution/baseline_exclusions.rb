# frozen_string_literal: true

module Kimera
  module Execution
  end
end

class Kimera::Execution::BaselineExclusions
  LISTED = 5

  def initialize(failures)
    @failures = failures
  end

  def to_s
    return if @failures.empty?
    [headline, *listed, overflow].compact.join("\n")
  end

  private

  def headline
    "kimera: #{@failures.size} failing test(s) cover no in-scope mutant and were " \
      "excluded from the baseline (they gate nothing this run):"
  end

  def listed = @failures.first(LISTED).map { |test_id, failure| "  #{test_id}#{reason(failure)}" }

  def reason(failure)
    first = failure.to_s.lines.first.to_s.strip
    first.empty? ? "" : ": #{first}"
  end

  def overflow
    hidden = @failures.size - LISTED
    "  … and #{hidden} more" if hidden.positive?
  end
end
