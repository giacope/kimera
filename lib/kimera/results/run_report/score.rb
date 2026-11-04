# frozen_string_literal: true

class Kimera::RunReport::Score
  CONDITIONAL = %i[uncovered_by_unit harness_error ignored isolated_only unmutatable leaks].freeze
  REPORTED = %i[
    survived timeout error no_coverage uncovered_by_unit harness_error ignored isolated_only unmutatable
  ].freeze
  LABELS = { total: "mutants", harness_error: "unjudged" }.freeze

  def initialize(results, leaks, counted)
    @results = results
    @leaks = leaks
    @counted = counted
  end

  def to_h = { total: @results.size, killed: killed.size, leaks: @leaks.size, **reported }

  def to_f
    total = covered.size
    return 1.0 if total.zero?
    Float(killed.size) / total
  end

  def percent = covered.empty? ? "n/a" : format("%.1f%%", to_f * 100)

  def by_file
    @results.group_by { |result| result.to_h.fetch("file").to_s }
      .transform_values { |part| self.class.new(part, @leaks, @counted) }
  end

  def to_s
    tallies = to_h
    tallies.filter_map { |key, count| labeled(key, count) }.insert(tallies.size - CONDITIONAL.size, scoreline).join(" ")
  end

  private

  def killed = @results.select(&:killed?)

  def covered = @results.select { |result| result.covered? || result.status?(*@counted) }

  def reported = REPORTED.to_h { |status| [status, @results.count { |result| result.status?(status) }] }

  def labeled(key, count)
    return if CONDITIONAL.include?(key) && count.zero?
    "#{LABELS.fetch(key, key)}=#{count}"
  end

  def scoreline
    return "score=n/a (nothing to mutate)" if @results.empty?
    return "score=n/a (0 of #{@results.size} mutants evaluated)" if covered.empty?
    text = "score=#{percent}"
    count = @results.count { |result| result.status?(:no_coverage) }
    return text unless count.positive?
    return "#{text} (#{count} uncovered scored as not killed)" if @counted.include?(:no_coverage)
    "#{text} (#{count} uncovered not scored)"
  end
end
