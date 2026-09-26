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

  def reasons = @_reasons ||= [survivors, coverage, ignored, unjudged].compact

  def survivors
    max = @options[:max_survivors]
    count = @report.survived.size
    return unless max ? count > max : count.positive?
    "survivors=#{count} > max_survivors=#{max || 0}"
  end

  def coverage
    uncovered = @report.uncovered.size
    return unless @options[:fail_on_no_coverage] && uncovered.positive?
    "#{uncovered} mutant(s) with no covering test (--fail-on-no-coverage)"
  end

  def ignored
    cap = @options[:max_ignored]
    count = @report.statuses(:ignored).size
    "ignored=#{count} > max_ignored=#{cap}" if cap && count > cap
  end

  def unjudged
    count = @report.errors.size
    cap = Integer(@options[:max_errors] || 0)
    "unjudged=#{count} > max_errors=#{cap}" if count > cap
  end
end
