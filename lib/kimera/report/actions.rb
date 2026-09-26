# frozen_string_literal: true

module Kimera
  module Report
  end
end

class Kimera::Report::Actions
  def initialize(io: $stdout)
    @io = io
  end

  def show(report, path: nil)
    lines = [survivors(report.survived, path), uncovered(report.uncovered, path), unjudged(report.errors)].compact
    @io.puts("", "Next actions:", *lines) unless lines.empty?
  end

  private

  def survivors(found, path)
    first = found.min_by(&:mutant_id)
    first && advice(found, "surviving mutant(s): inspect ##{first.mutant_id} with `#{inspection(first, path)}`")
  end

  def inspection(first, path)
    path ? "kimera mutant #{first.mutant_id} --report #{path}" : "kimera run --report tmp/kimera.json"
  end

  def uncovered(found, path) = advice(found, "uncovered mutant(s): #{listing(path)}")

  def listing(path) = path ? "kimera report #{path} --status no_coverage" : "rerun with --report tmp/kimera.json"

  def unjudged(found) = advice(found, "unjudged mutant(s): retry with `kimera run --isolated`")

  def advice(found, text)
    "  #{found.size} #{text}" unless found.empty?
  end
end
