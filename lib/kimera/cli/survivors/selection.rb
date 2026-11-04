# frozen_string_literal: true

class Kimera::CLI::Survivors::Selection
  STATUSES = { "unjudged" => "harness_error" }.freeze

  def initialize(status, filter, report, narrowed)
    @status = status
    @filter = filter
    @report = report
    @narrowed = narrowed
  end

  def listed(results, panel)
    found = matching(results)
    found.empty? ? ["no #{@status} mutants#{" matching #{@filter}" if @filter}"] : panel.announce(found, self)
  end

  def heading(count) = "#{count} #{@status} mutant(s)#{narrowing}:"

  def detail = "detail: kimera mutant <ID|KEY> --report #{@report}"

  private

  def matching(results)
    status = STATUSES.fetch(@status, @status)
    found = results.select { |row| row["status"] == status }.map { |row| [row["file"].to_s, row["line"] || 0, row] }
    @filter ? found.select { |file,| file.include?(@filter) } : found
  end

  def narrowing = @narrowed && @status == "no_coverage" ? ", not covered by the narrowed tests" : ""
end
