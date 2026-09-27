# frozen_string_literal: true

class Kimera::Execution::BaselineFailure::Breakdown
  MAX_FAILURES = 5
  PRECEDING = 3

  def initialize(failed, workers)
    @failed = failed
    @workers = workers
  end

  def to_s
    lines = @workers.sort_by(&:first).filter_map { |slot, ids| worker(slot, ids) }
    lines.empty? ? "" : "\n  per worker (tests in the order it ran them):\n#{lines.join("\n")}"
  end

  private

  def worker(slot, ids)
    hits = ids.each_index.select { |index| @failed.include?(ids[index]) }
    return if hits.empty?
    "    worker #{slot}: ran #{ids.size}; failed #{failures(ids, hits)}#{preceding(ids, hits.first)}"
  end

  def failures(ids, hits)
    shown = hits.first(MAX_FAILURES).map { |index| "##{index + 1} #{ids[index]}" }
    extra = hits.size - shown.size
    shown.join(", ") + (extra.positive? ? " (+#{extra} more)" : "")
  end

  def preceding(ids, first)
    before = ids[[first - PRECEDING, 0].max...first]
    before.empty? ? " (first test on this worker)" : "; just before: #{before.join(", ")}"
  end
end
