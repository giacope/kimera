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

  def reasons = @_reasons ||= [survivors, coverage, ignored, unjudged, untested].compact

  def survivors
    max = @options[:max_survivors]
    unowned = @report.unattributed.size
    count = @report.survived.size + unowned
    return unless max ? count > max : count.positive?
    "survivors=#{count}#{" (#{unowned} uncovered_by_unit)" if unowned.positive?} > max_survivors=#{max || 0}"
  end

  def coverage
    uncovered = @report.uncovered.size
    return unless uncovered.positive?
    return "#{uncovered} mutant(s) with no covering test (--fail-on-no-coverage)" if @options[:fail_on_no_coverage]
    "#{uncovered} mutant(s) with no covering test (count_no_coverage)" if counted?
  end

  def counted? = @options[:count_no_coverage] && !@options[:narrowed]

  def ignored
    cap = @options[:max_ignored]
    count = @report.statuses(:ignored).size
    "ignored=#{count} > max_ignored=#{cap}" if cap && count > cap
  end

  def unjudged
    count = @report.errors.size
    cap = Integer(@options[:max_errors] || 0)
    "unjudged=#{count} > max_errors=#{cap} (status harness_error in the JSON report)" if count > cap
  end

  def untested
    pending = @report.statuses(:isolated_only).size + @report.statuses(:unmutatable).size
    return unless pending.positive? && @report.killed.empty?
    "0 of #{@report.results.size} mutants killed: #{pending} only the isolated tier can judge (run with --isolated)"
  end
end
