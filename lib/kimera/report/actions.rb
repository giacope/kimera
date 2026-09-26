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
    hints = path ? SavedHints.new(path) : UnsavedHints.new
    lines = [
      advice(report.survived, hints, :survivors), advice(report.uncovered, hints, :uncovered),
      advice(report.errors, hints, :unjudged)
    ].compact
    @io.puts("", "Next actions:", *lines) unless lines.empty?
  end

  private

  def advice(found, hints, kind)
    first = found.min_by(&:mutant_id)
    "  #{found.size} #{hints.public_send(kind, first.mutant_id)}" if first
  end

  class SavedHints
    def initialize(path)
      @path = path
    end

    def survivors(id) = "surviving mutant(s): inspect ##{id} with `#{mutant(id)}`"

    def uncovered(_id) = "uncovered mutant(s): kimera report #{@path} --status no_coverage"

    def unjudged(id) = "unjudged mutant(s): see why with `#{mutant(id)}`"

    private

    def mutant(id) = "kimera mutant #{id} --report #{@path}"
  end

  class UnsavedHints
    def survivors(id) = "surviving mutant(s): inspect ##{id} with `kimera run --report tmp/kimera.json`"

    def uncovered(_id) = "uncovered mutant(s): rerun with --report tmp/kimera.json"

    def unjudged(_id) = "unjudged mutant(s): retry with `kimera run --isolated`"
  end
end
