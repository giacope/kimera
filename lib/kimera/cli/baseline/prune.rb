# frozen_string_literal: true

require "yaml"

class Kimera::CLI::Baseline::Prune
  class Tense
    def initialize(removed, holds)
      @removed = removed
      @holds = holds
    end

    def removal(count, path) = "#{@removed} #{count} entr(ies) from #{path}:"

    def holding(path, count) = "#{path} #{@holds} #{count} accepted mutant(s) "
  end
  DONE = Tense.new("Removed", "now holds")
  PREVIEW = Tense.new("Would remove", "would hold")

  def initialize(ledger, io: $stdout, listing: Kimera::CLI::Baseline::Listing.new(io))
    @ledger = ledger
    @io = io
    @listing = listing
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
    @listing.show(tense.removal(dropped.size, @ledger.path), dropped) { |entry| "  - #{entry.place} (#{entry.kind})" }
  end

  def anchored
    @listing.show("Re-anchored #{moved.size} entr(ies) to their mutant's current line:", moved) do |entry|
      "  #{entry.place}"
    end
  end

  def total(tense)
    @io.puts(
      "#{tense.holding(@ledger.path, kept.size)}" \
        "(was #{entries.size}); max_ignored can be lowered by #{dropped.size}."
    )
  end
end
