# frozen_string_literal: true

require "yaml"

class Kimera::CLI::Baseline::Prune
  Tense = Data.define(:removed, :holds)
  DONE = Tense.new("Removed", "now holds")
  PREVIEW = Tense.new("Would remove", "would hold")

  def initialize(ledger, io: $stdout)
    @ledger = ledger
    @io = io
  end

  def preview
    summarize(PREVIEW)
    @io.puts("(dry run: #{@ledger.path} is unchanged)")
    0
  end

  def apply
    summarize(DONE)
    File.write(@ledger.path, YAML.dump(pruned)) if changed?
    0
  end

  private

  def entries = @ledger.entries

  def dropped = entries.select(&:prunable?)

  def kept = entries.reject(&:prunable?)

  def moved = kept.select(&:moved)

  def changed? = !(dropped.empty? && moved.empty?)

  def pruned = @ledger.document.merge("ignore" => kept.map(&:kept))

  def summarize(tense)
    return unchanged unless changed?
    removed(tense)
    anchored
    total(tense)
  end

  def unchanged = @io.puts("Nothing to prune: #{@ledger.path} keeps its #{entries.size} accepted mutant(s).")

  def removed(tense)
    return if dropped.empty?
    @io.puts("#{tense.removed} #{dropped.size} entr(ies) from #{@ledger.path}:")
    dropped.each { |entry| @io.puts("  - #{entry.place} (#{entry.kind})") }
  end

  def anchored
    return if moved.empty?
    @io.puts("Re-anchored #{moved.size} entr(ies) to their mutant's current line:")
    moved.each { |entry| @io.puts("  #{entry.place}") }
  end

  def total(tense)
    @io.puts(
      "#{@ledger.path} #{tense.holds} #{kept.size} accepted mutant(s) " \
        "(was #{entries.size}); max_ignored can be lowered by #{dropped.size}."
    )
  end
end
