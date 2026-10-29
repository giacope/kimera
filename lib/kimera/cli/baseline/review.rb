# frozen_string_literal: true

require_relative "../outcome"

class Kimera::CLI::Baseline::Review
  class Group
    def initialize(kind, title)
      @kind = kind
      @title = title
    end

    def lines(entries)
      held = entries.select { |entry| entry.kind?(@kind) }
      listing = Kimera::CLI::Baseline::Listing.new(["", "#{@title} (#{held.size}):"], held)
      listing.lines { |place, _kind, verdicts, reason| "  #{place}#{verdicts} — #{reason}" }
    end
  end
  GROUPS = [
    Group.new(:killed, "Killed, safe to prune"),
    Group.new(:surviving, "Still surviving"),
    Group.new(:unjudged, "Unjudged (no verdict in this report)"),
    Group.new(:stale, "Stale: the report covers the file, but no mutant matches"),
    Group.new(:out_of_scope, "Not in the report's scope")
  ].freeze
  PRUNABLE = %i[killed stale].freeze

  def show(ledger, path, report)
    entries = ledger.entries
    lines = ["#{entries.size} accepted mutant(s) in #{path}, judged against #{report}:"]
      .concat(GROUPS.flat_map { |group| group.lines(entries) }, advice(entries, "#{path} --report #{report}"))
    Kimera::CLI::Outcome::Said.new(*lines)
  end

  private

  def advice(entries, files)
    prunable = entries.count { |entry| entry.kind?(*PRUNABLE) }
    pruning = prunable.zero? ? [] : ["", "Prune #{prunable} entr(ies): kimera baseline prune #{files}"]
    [*unevaluated(entries.count { |entry| entry.status?("ignored") }), *pruning]
  end

  def unevaluated(count)
    return [] if count.zero?
    ["", "#{count} entr(ies) were not evaluated: rerun with `kimera run --evaluate-ignored --report FILE`"]
  end
end
