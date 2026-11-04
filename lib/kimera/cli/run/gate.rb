# frozen_string_literal: true

class Kimera::CLI::Run::Gate
  def initialize(report, options)
    @report = report
    @options = options
  end

  def status(stream)
    return 0 if reasons.empty?
    reasons.each { |reason| stream.puts("kimera: gate failed: #{reason}") }
    2
  end

  private

  def reasons = @_reasons ||= [*survivors, *coverage, *ignored, *unjudged, *untested]

  def survivors
    max = @options[:max_survivors]
    unowned = tally(:uncovered_by_unit)
    count = tally(:survived) + unowned
    return [] unless max ? count > max : count.positive?
    ["survivors=#{count}#{" (#{unowned} uncovered_by_unit)" if unowned.positive?} > max_survivors=#{max || 0}"]
  end

  def coverage
    uncovered = tally(:no_coverage)
    return [] unless uncovered.positive?
    return ["#{uncovered} mutant(s) with no covering test (--fail-on-no-coverage)"] if @options[:fail_on_no_coverage]
    counted? ? ["#{uncovered} mutant(s) with no covering test (count_no_coverage)"] : []
  end

  def tally(status) = (@_tally ||= @report.score.to_h).fetch(status)

  def counted? = @options[:count_no_coverage] && !@options[:narrowed]

  def ignored
    cap = @options[:max_ignored]
    count = tally(:ignored)
    cap && count > cap ? ["ignored=#{count} > max_ignored=#{cap}"] : []
  end

  def unjudged
    count = tally(:harness_error)
    cap = Integer(@options[:max_errors] || 0)
    count > cap ? ["unjudged=#{count} > max_errors=#{cap} (status harness_error in the JSON report)"] : []
  end

  def untested
    pending = tally(:isolated_only) + tally(:unmutatable)
    return [] unless pending.positive? && tally(:killed).zero?
    ["0 of #{tally(:total)} mutants killed: #{pending} only the isolated tier can judge (run with --isolated)"]
  end
end
