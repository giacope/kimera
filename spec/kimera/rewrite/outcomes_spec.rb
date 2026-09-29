# frozen_string_literal: true

require "prism"
require "kimera/rewrite/outcomes"

RSpec.describe(Kimera::Rewrite::Outcomes) do
  def at(source, snippet)
    start = source.byteindex(snippet)
    Prism::Location.new(Prism.parse(source).source, start, snippet.bytesize)
  end

  def distinct(source, snippet, directives)
    described_class.new(source).distinct(at(source, snippet), directives.each_index.to_a) { directives[it] }
  end

  def drops(count) = Array.new(count) { |index| { "type" => "drop_argument", "index" => index } }

  it "keeps the first directive of each program", :aggregate_failures do
    expect(distinct("f(1, 1, 2, 1)\n", "f(1, 1, 2, 1)", drops(4))).to(eq([0, 2, 3]))
    expect(distinct("f(a)\n", "f(a)", [{ "type" => "statement_deletion" }, { "type" => "return_nil" }])).to(eq([0, 1]))
  end

  it "compares programs up to parentheses and minus on a numeric literal", :aggregate_failures do
    expect(distinct("f(-(1), (-1), -(-(1)), 1)\n", "f(-(1), (-1), -(-(1)), 1)", drops(4))).to(eq([0, 2]))
    expect(distinct("f(0.0, -(0.0), -0.0)\n", "f(0.0, -(0.0), -0.0)", drops(3))).to(eq([0, 1]))
  end

  it "reads a node by its span in a multibyte file" do
    expect(distinct("\"é\"\nf(1, 1)\n", "f(1, 1)", drops(2))).to(eq([0]))
  end

  it "keeps apart what it can't render, unless the directives are the same", :aggregate_failures do
    unknown = { "type" => "unknown" }
    expect(distinct("f(1)\n", "f(1)", [unknown, unknown.merge("to" => 1), unknown])).to(eq([0, 1]))
    expect(distinct("f(1, 1)\n", "1, 1", drops(2))).to(eq([0, 1]))
    expect(distinct("f(1, 1)\n\"\\xff\"\n", "f(1, 1)", drops(2))).to(eq([0, 1]))
  end
end
