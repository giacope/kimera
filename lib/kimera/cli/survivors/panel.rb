# frozen_string_literal: true

require_relative "../../support/readout"
require_relative "context"

class Kimera::CLI::Survivors::Panel
  def initialize(io: $stdout, tests: {}, root: ".")
    @io = io
    @tests = tests
    @root = root
  end

  def announce(matching, options)
    @io.puts("#{matching.size} #{options[:status]} mutant(s):")
    sorted(matching).each { |row| entry(row) }
    @io.puts
    @io.puts("detail: kimera mutant <ID|KEY> --report #{options[:report]}")
  end

  def describe(row)
    header(row)
    body(row)
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
    field("at:       ", position(row))
    field("operator: ", row["operator"])
    field("label:    ", row["label"])
  end

  def extra(row)
    seconds = row["duration"]
    @io.puts("  duration: #{Kimera::Readout.brief(seconds)}") if seconds&.positive?
    detail(row["detail"])
    field("note:     ", row["note"])
  end

  def field(prefix, value)
    @io.puts("  #{prefix}#{value}") if value
  end

  def detail(text)
    first, *rest = Kimera::Readout.lines(text)
    field("detail:   ", first)
    rest.each { |line| @io.puts("            #{line}") }
  end

  def body(row)
    diff(row, "  ")
    context(row)
  end

  def context(row)
    lines = Kimera::CLI::Survivors::Context.new(row, root: @root).lines
    @io.puts("", *lines, "") unless lines.empty?
  end

  def position(row)
    column = row["column"]
    return unless column
    method = row["method"]
    "#{row["file"]}:#{row["line"]}:#{column}#{"  in #{method}" if method}"
  end

  def brief(row)
    method = row["method"]
    @io.puts("  ##{row["mutant_id"]}  #{location(row)}#{"  in #{method}" if method}  [#{row["label"]}]")
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
    items.each { |test| @io.puts("    #{Kimera::Readout.label(test, @tests.fetch(test, {}))}") }
  end

  def location(row)
    row["key"] || [row["file"], row["line"]].compact.join(":")
  end
end
