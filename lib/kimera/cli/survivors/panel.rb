# frozen_string_literal: true

require_relative "../../support/duration"

class Kimera::CLI::Survivors::Panel
  def initialize(io: $stdout)
    @io = io
  end

  def announce(matching, options)
    @io.puts("#{matching.size} #{options[:status]} mutant(s):")
    sorted(matching).each { |row| entry(row) }
    @io.puts
    @io.puts("detail: kimera mutant <ID|KEY> --report #{options[:report]}")
  end

  def describe(row)
    header(row)
    diff(row, "  ")
    extra(row)
    tests("covering tests", row["covering_tests"])
    tests("failing tests", row["failing_tests"])
  end

  private

  def entry(row)
    @io.puts
    brief(row)
  end

  def sorted(matching)
    matching.sort_by { |file, line,| [file, line] }.map { |_, _, row| row }
  end

  def header(row)
    @io.puts("##{row["mutant_id"]}  #{row["status"]}  #{location(row)}")
    field("operator: ", row["operator"])
    field("label:    ", row["label"])
  end

  def extra(row)
    seconds = row["duration"]
    @io.puts("  duration: #{Kimera::Duration.new(seconds).brief}") if seconds&.positive?
    field("detail:   ", row["detail"])
  end

  def field(prefix, value)
    @io.puts("  #{prefix}#{value}") if value
  end

  def brief(row)
    @io.puts("  ##{row["mutant_id"]}  #{location(row)}  [#{row["label"]}]")
    diff(row, "    ")
    covering = Array(row["covering_tests"])
    @io.puts("    covered by #{covering.size} test(s)") unless covering.empty?
  end

  def diff(row, indent)
    source(row["original"], "-", indent)
    mutated = row["mutated"]
    source(mutated, "+", indent) if mutated
  end

  def source(code, sign, indent)
    first, *rest = code.to_s.split("\n")
    @io.puts("#{indent}#{sign} #{first}")
    rest.each { |line| @io.puts("#{indent}  #{line}") }
  end

  def tests(title, items)
    items = Array(items)
    return if items.empty?
    @io.puts("  #{title} (#{items.size}):")
    items.each { |test| @io.puts("    #{test}") }
  end

  def location(row)
    row["key"] || [row["file"], row["line"]].compact.join(":")
  end
end
