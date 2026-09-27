# frozen_string_literal: true

class Kimera::CLI::Baseline::Review
  Group =
    Data.define(:kind, :title) do
      def entries(grouped) = grouped.fetch(kind, [])

      def heading(count) = "#{title} (#{count}):"
    end
  GROUPS = [
    Group.new(:killed, "Killed, safe to prune"),
    Group.new(:surviving, "Still surviving"),
    Group.new(:unjudged, "Unjudged (no verdict in this report)"),
    Group.new(:stale, "Stale: the report covers the file, but no mutant matches"),
    Group.new(:out_of_scope, "Not in the report's scope")
  ].freeze

  def initialize(io: $stdout)
    @io = io
  end

  def show(ledger)
    entries = ledger.entries
    @io.puts("#{entries.size} accepted mutant(s) in #{ledger.path}, judged against #{ledger.report}:")
    groups(entries.group_by(&:kind))
    advise(ledger, entries)
    0
  end

  private

  def groups(grouped) = GROUPS.each { |group| list(group, group.entries(grouped)) }

  def list(group, entries)
    return if entries.empty?
    @io.puts("", group.heading(entries.size))
    entries.each { |entry| @io.puts("  #{entry.place}#{verdicts(entry)} — #{entry.fields["reason"]}") }
  end

  def verdicts(entry)
    statuses = entry.statuses
    statuses.empty? ? "" : " (#{statuses.join(", ")})"
  end

  def advise(ledger, entries)
    unevaluated(entries.count { |entry| entry.statuses.include?("ignored") })
    prunable = entries.count(&:prunable?)
    return if prunable.zero?
    @io.puts("", "Prune #{prunable} entr(ies): kimera baseline prune #{ledger.path} --report #{ledger.report}")
  end

  def unevaluated(count)
    return if count.zero?
    @io.puts("", "#{count} entr(ies) were not evaluated: rerun with `kimera run --evaluate-ignored --report FILE`")
  end
end
