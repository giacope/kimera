# frozen_string_literal: true

require "yaml"
require_relative "../outcome"

class Kimera::CLI::Baseline::Prune
  class Tense
    def initialize(removed, holds)
      @removed = removed
      @holds = holds
    end

    def removal(count, path) = "#{@removed} #{count} entr(ies) from #{path}:"

    def holding(path, count) = "#{path} #{@holds} #{count} accepted mutant(s) "
  end
  PRUNABLE = %i[killed stale].freeze
  DONE = Tense.new("Removed", "now holds")
  PREVIEW = Tense.new("Would remove", "would hold")

  def initialize(ledger, path)
    @ledger = ledger
    @path = path
  end

  def preview = said(*summary(PREVIEW), "(dry run: #{@path} is unchanged)")

  def apply
    lines = summary(DONE)
    prune if changed?
    said(*lines)
  end

  private

  def entries = @ledger.entries

  def dropped = entries.select { |entry| entry.kind?(*PRUNABLE) }

  def kept = entries.reject { |entry| entry.kind?(*PRUNABLE) }

  def moved = kept.select(&:moved?)

  def changed? = !(dropped.empty? && moved.empty?)

  def pruned = @ledger.document.merge("ignore" => kept.map(&:to_h))

  def prune = File.write(@path, YAML.dump(pruned))

  def said(*lines) = Kimera::CLI::Outcome::Said.new(*lines)

  def summary(tense)
    return ["Nothing to prune: #{@path} keeps its #{entries.size} accepted mutant(s)."] unless changed?
    [*removed(tense), *anchored, total(tense)]
  end

  def removed(tense)
    Kimera::CLI::Baseline::Listing.new(tense.removal(dropped.size, @path), dropped).lines { |place, kind| "  - #{place} (#{kind})" }
  end

  def anchored
    heading = "Re-anchored #{moved.size} entr(ies) to their mutant's current line:"
    Kimera::CLI::Baseline::Listing.new(heading, moved).lines { |place| "  #{place}" }
  end

  def total(tense)
    "#{tense.holding(@path, kept.size)}(was #{entries.size}); max_ignored can be lowered by #{dropped.size}."
  end
end
