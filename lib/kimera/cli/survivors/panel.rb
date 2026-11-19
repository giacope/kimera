# frozen_string_literal: true

require_relative "../../support/readout"
require_relative "../../mutated_text"
require_relative "../../operators"
require_relative "../../report/palette"
require_relative "context"

class Kimera::CLI::Survivors::Panel
  EXTENDED = "%d from the extended operators, which more often mark code no test can tell apart:"

  def initialize(tests: {}, root: ".", color: nil, palette: Kimera::Report::Palette.new($stdout, color))
    @tests = tests
    @root = root
    @palette = palette
  end

  def announce(matching, selection)
    core, extended = sorted(matching).partition { |row| core?(row) }
    [selection.heading(matching.size), *core.flat_map { |row| entry(row) }, *aside(core, extended)]
      .push("", selection.detail)
  end

  def describe(row)
    [*header(row), *body(row), *extra(row), *tests("covering tests", row["covering_tests"])]
      .concat(tests("failing tests", row["failing_tests"]))
  end

  private

  def entry(row) = ["", *brief(row)]

  def core?(row, core = Kimera::Operators.build.map(&:key)) = row["operator"].to_s.split("+").intersect?(core)

  def aside(core, extended)
    return extended.flat_map { |row| entry(row) } if core.empty? || extended.empty?
    ["", format(EXTENDED, extended.size), *extended.flat_map { |row| entry(row) }]
  end

  def sorted(matching)
    matching.sort_by { |file, line,| [file, line] }.map { |_, _, row| row }
  end

  def header(row)
    ["##{row["mutant_id"]}  #{row["status"]}  #{location(row)}", *field("at:       ", position(row))]
      .concat(field("operator: ", row["operator"]), field("label:    ", row["label"]))
  end

  def extra(row)
    seconds = row["duration"]
    lasted = seconds&.positive? ? ["  duration: #{Kimera::Readout.new(seconds).brief}"] : []
    [*lasted, *detail(row["detail"]), *field("note:     ", row["note"])]
  end

  def field(prefix, value) = value ? ["  #{prefix}#{value}"] : []

  def detail(text)
    first, *rest = Kimera::Readout.new(text).lines
    [*field("detail:   ", first), *rest.map { |line| "            #{line}" }]
  end

  def body(row) = [*diff(row, "  "), *context(row)]

  def context(row)
    lines = Kimera::CLI::Survivors::Context.new(row, root: @root).lines
    lines.empty? ? [] : ["", *lines, ""]
  end

  def position(row)
    column = row["column"]
    return unless column
    method = row["method"]
    "#{row["file"]}:#{row["line"]}:#{column}#{"  in #{method}" if method}"
  end

  def brief(row)
    method = row["method"]
    covering = Array(row["covering_tests"])
    ["  ##{row["mutant_id"]}  #{location(row)}#{"  in #{method}" if method}  [#{row["label"]}]", *diff(row, "    ")]
      .concat(covering.empty? ? [] : ["    covered by #{covering.size} test(s)"])
  end

  def diff(row, indent)
    original = row["original"]
    mutated = original ? [source(Kimera::MutatedText.new(Array(row["mutated"])).to_s, @palette.green("+"), indent)] : []
    [source(original, @palette.red("-"), indent), *mutated]
  end

  def source(code, sign, indent) = Kimera::Readout.new(code).quoted(sign, indent)

  def tests(title, items)
    items = Array(items)
    return [] if items.empty?
    ["  #{title} (#{items.size}):", *items.map { |test| "    #{label(test)}" }]
  end

  def label(test) = Kimera::Readout::Label.new(test, @tests.fetch(test, {})).text

  def location(row)
    row["key"] || [row["file"], row["line"]].compact.join(":")
  end
end
