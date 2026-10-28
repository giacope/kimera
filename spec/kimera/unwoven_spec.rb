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

  it "keeps a rewrite that groups a pattern or spells a string by its escapes (R6B5-M1)", :aggregate_failures do
    original = "def status(r)\n  case r\n  in {code: 200 | 201} then :ok\n  end\nend\n"
    woven = "def status(r)\n  case r\n  in { code: (200 | 201) } then #{guard(1, ":x", ":ok")}\n  end\nend\n"
    expect(keeps?(woven, original)).to(be(true))
    greeting = "def text = [#{guard(1, %(""), %("Gr\\u{FC}\\u{DF}e"))}, :de]\n"
    expect(keeps?(greeting, "def text = [\"Grüße\", :de]\n")).to(be(true))
  end

  it "reads a visibility probe and its registrations as nothing", :aggregate_failures do
    probe = "if ::Kimera::RUNTIME.active?(2) then nil else #{guard(3, "nil", "nil")} end"
    woven = "def x\n  #{probe}; 1\nend\n::Kimera::RUNTIME.privatize(2, self, :x)\n"
    expect(keeps?(woven, "def x\n  1\nend\n")).to(be(true))
    expect(keeps?("def x\n  if ::Kimera::RUNTIME.active?(2) then 1 else nil end\n  1\nend\n", "def x\n  1\nend\n"))
      .to(be(false))
  end

  it "reads a guard over several statements as those statements", :aggregate_failures do
    expect(keeps?("def f\n  #{guard(1, "nil", "a\n  b")}\nend\n", "def f\n  a\n  b\nend\n")).to(be(true))
    expect(keeps?("def f\n  #{guard(1, "nil", "a; b")}\n  c\nend\n", "def f\n  a; b\n  c\nend\n")).to(be(true))
  end

  # R6B5-M2: the rewrite joined the method onto its first line and padded the
  # lines it lost before its `end`; `__LINE__` read 2 for 8, and every
  # backtrace, coverage line and `class_eval ..., __LINE__ + 1` moved with it.
  def trace = "def mark(l)\n  begin\n    l.fetch(0)\n  rescue IndexError\n    nil\n  end\n  [:seen, __LINE__]\nend\n"

  def begun = "begin\n    l.fetch(0)\n  rescue IndexError\n    nil\n  end"

  it "refuses a rewrite that moves a line of the method (R6B5-M2)", :aggregate_failures do
    joined = "def mark(l); #{guard(1, "l.fetch(0)", begun.gsub(/\n */, "; "))}; [:seen, __LINE__]#{"\n" * 6}end\n"
    expect(keeps?(joined, trace)).to(be(false))
    expect(keeps?("def mark(l)\n  #{guard(1, "l.fetch(0)", begun)}\n  [:seen, __LINE__]\nend\n", trace)).to(be(true))
  end

  it "reads back a class the overlay rewrote whole, and refuses it moved (R6B5-M2)", :aggregate_failures do
    original = "class Conf\n  define_method(:size) do\n    [:size, __LINE__]\n  end\nend\n"
    laid = "class Conf\n  define_method(:size) do\n    [#{guard(1, ":x", ":size")}, __LINE__]\n  end\nend\n"
    expect(keeps?(laid, original)).to(be(true))
    expect(keeps?("class Conf; define_method(:size) { [:size, __LINE__] }\n\n\nend\n", original)).to(be(false))
  end

  # A holder is found by its kind, its line and its name, whatever else on
  # the file shares one of them.
  it "finds the method it rewrote among others of its name or line", :aggregate_failures do
    twice = "def of = 1\ndef of = 2\n"
    expect(described_class.new(tree(twice)).keeps?([tree(twice).statements.body.last])).to(be(true))
    beside = "of = 1; def of = 2\n"
    expect(described_class.new(tree(beside)).keeps?([tree(beside).statements.body.last])).to(be(true))
  end

  it "reads a probe before a body of statements as nothing, every statement on its line" do
    expect(keeps?("def x; ::Kimera::RUNTIME.active?(2)\n  a\n  b\nend\n", "def x\n  a\n  b\nend\n")).to(be(true))
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

  def tests(*ids) = ids.map { |id| "::Kimera::RUNTIME.active?(#{id})" }.join(" || ")

  # The guard a point gets in place: the original first, under the negated
  # tests, then each mutant.
  it "reads a guard written in place as its original", :aggregate_failures do
    woven = "def f(a)\n  (!(#{tests(1, 2)}) ? (a > 1) : #{tests(1)} ? (a >= 1) : (a < 1))\nend\n"
    expect(keeps?(woven, "def f(a)\n  a > 1\nend\n")).to(be(true))
    expect(keeps?("def f(a) = (!((#{tests(3)})) ? (a) : (nil))\n", "def f(a) = a\n")).to(be(true))
    expect(keeps?(woven, "def f(a)\n  a >= 1\nend\n")).to(be(false))
  end

  test = "::Kimera::RUNTIME.active?(1)"
  {
    "a call on another receiver" => "Other.active?(1)", "one beside another call" => "#{test} || Other.active?(2)",
    "both tests at once" => "#{test} && #{test}", "nothing" => "", "two statements" => "#{test}; 2"
  }.each do |kind, tested|
    it "reads a negation of #{kind} as it is" do
      expect(keeps?("def f(a) = (!(#{tested}) ? (a) : (nil))\n", "def f(a) = a\n")).to(be(false))
    end
  end

  it "reads other calls on the runtime and on other receivers as they are", :aggregate_failures do
    expect(keeps?("def f\n  ::Kimera::RUNTIME.reset!\n  1\nend\n", "def f\n  1\nend\n")).to(be(false))
    expect(keeps?("def f\n  Other.active?(1)\n  1\nend\n", "def f\n  1\nend\n")).to(be(false))
    expect(keeps?("def f\n  if active?(1) then 2 else 1 end\nend\n", "def f\n  1\nend\n")).to(be(false))
  end
end
