# frozen_string_literal: true

require "kimera/synthesis/unwoven"

# The warm overlay rewrites a whole method when it cannot guard a point in
# place. With every mutant off that method must be the original: its guards
# (`if ::Kimera::RUNTIME.active?(id)`) read as their else side, a visibility
# probe and its registration as nothing, and the rest as the original reads,
# compared as an Outline (no locations, a lone expression in parentheses as the
# expression, a string by its value however its parts split, an integer in any
# base). R6B4-M1..M3: the rewrite read `when 90.. then "A"` as `when 90.."A"`,
# `in %w[a b]` as an array pattern and `"\u{3042}"` as binary, and kimera ran it.
RSpec.describe(Kimera::Unwoven) do
  def tree(source) = Kimera::Syntax.parse(source).value

  def definition(source) = tree(source).statements.body.first

  def keeps?(woven, original) = described_class.new(tree(woven)).keeps?([definition(original)])

  def guard(id, mutated, kept) = "if ::Kimera::RUNTIME.active?(#{id}) then #{mutated} else #{kept} end"

  def grade = "def of(score)\n  case score\n  when 90.. then \"A\"\n  end\nend\n"

  def graded(gap) = "def of(score)\n  case score\n  when 90..#{gap}#{guard(1, %(""), %("A"))}\n  end\nend\n"

  it "keeps a method whose guards read as the original with every mutant off" do
    expect(keeps?(graded("; "), grade)).to(be(true))
  end

  it "refuses a rewrite that reads as another method (R6B4-M1)" do
    expect(keeps?(graded("\n    "), grade)).to(be(false))
  end

  it "refuses an array pattern written for a word list (R6B4-M2)" do
    original = "def kind(v)\n  case v\n  in %w[a b] then :pair\n  end\nend\n"
    expect(keeps?("def kind(v)\n  case v\n  in [\"a\", \"b\"] then #{guard(1, ":x", ":pair")}\n  end\nend\n", original))
      .to(be(false))
  end

  def glyph(text) = "# encoding: binary\ndef glyph = #{text}\n"

  it "refuses a string written in another encoding (R6B4-M3)" do
    woven = [glyph(guard(1, %(""), %("\\xE3\\x81\\x82"))), glyph(guard(1, %(""), %("\\u{3042}")))]
    expect(woven.map { |text| keeps?(text, glyph(%("\\u{3042}"))) }).to(eq([false, true]))
  end

  it "reads a visibility probe and its registrations as nothing", :aggregate_failures do
    probe = "if ::Kimera::RUNTIME.active?(2) then nil else #{guard(3, "nil", "nil")} end"
    woven = "def x\n  #{probe}\n  1\nend\n::Kimera::RUNTIME.privatize(2, self, :x)\n"
    expect(keeps?(woven, "def x\n  1\nend\n")).to(be(true))
    expect(keeps?("def x\n  if ::Kimera::RUNTIME.active?(2) then 1 else nil end\n  1\nend\n", "def x\n  1\nend\n"))
      .to(be(false))
  end

  it "reads a guard over several statements as those statements", :aggregate_failures do
    expect(keeps?("def f\n  #{guard(1, "nil", "a; b")}\nend\n", "def f\n  a\n  b\nend\n")).to(be(true))
    expect(keeps?("def f\n  #{guard(1, "nil", "a; b")}\n  c\nend\n", "def f\n  a\n  b\n  c\nend\n")).to(be(true))
  end

  it "refuses a method the rewrite moved or lost", :aggregate_failures do
    expect(keeps?("\ndef of(score) = 1\n", "def of(score) = 1\n")).to(be(false))
    expect(keeps?("def other(score) = 1\n", "def of(score) = 1\n")).to(be(false))
    expect(described_class.new(tree("def a = 1\n")).keeps?([])).to(be(true))
  end

  it "names a block's numbered parameters as the overlay's tree does" do
    source = "def f(l) = l.map { _1 }.map { it }\n"
    named = Kimera::Rewrite::NumberedParams.new(tree(source)).normalize.statements.body.first
    expect(described_class.new(tree(source)).keeps?([named])).to(be(true))
  end

  it "reads other calls on the runtime and on other receivers as they are", :aggregate_failures do
    expect(keeps?("def f\n  ::Kimera::RUNTIME.reset!\n  1\nend\n", "def f\n  1\nend\n")).to(be(false))
    expect(keeps?("def f\n  Other.active?(1)\n  1\nend\n", "def f\n  1\nend\n")).to(be(false))
    expect(keeps?("def f\n  if active?(1) then 2 else 1 end\nend\n", "def f\n  1\nend\n")).to(be(false))
  end
end
