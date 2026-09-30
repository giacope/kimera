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

  # Only a bare literal: a bake writes `-(1.to_s)` as it reads, not as `-1.to_s`.
  it "keeps minus over a call on a literal apart from the call on the negative literal" do
    expect(distinct("f(-(1.to_s), (-1).to_s, -1.to_s)\n", "f(-(1.to_s), (-1).to_s, -1.to_s)", drops(3))).to(eq([0, 1]))
  end

  it "reads a node by its span in a multibyte file" do
    expect(distinct("\"é\"\nf(1, 1)\n", "f(1, 1)", drops(2))).to(eq([0]))
  end

  # unparser 0.9 can't write an array range endpoint; programs compare as trees.
  it "compares programs unparser can't write" do
    expect(distinct("f([a, a]...a, [a, a]...a)\n", "f([a, a]...a, [a, a]...a)", drops(2))).to(eq([0]))
  end

  it "keeps apart what it can't render, unless the directives are the same", :aggregate_failures do
    unknown = { "type" => "unknown" }
    expect(distinct("f(1)\n", "f(1)", [unknown, unknown.merge("to" => 1), unknown])).to(eq([0, 1]))
    expect(distinct("f(1, 1)\n", "1, 1", drops(2))).to(eq([0, 1]))
    expect(distinct("f(1, 1)\n/\\xff/\n", "f(1, 1)", drops(2))).to(eq([0, 1]))
  end

  it "reads a file with a string escape that is invalid UTF-8" do
    expect(distinct("f(1, 1)\n\"\\xff\"\n", "f(1, 1)", drops(2))).to(eq([0]))
  end

  describe "#writable" do
    def writable(source, snippet, directives)
      described_class.new(source).writable(at(source, snippet), directives.each_index.to_a) { directives[it] }
    end

    let(:unwrap) { [{ "type" => "unwrap_receiver" }, { "type" => "return_nil" }] }

    it "drops a variant that leaves a range literal where the node is tested", :aggregate_failures do
      expect(writable("if (a...b).to_a then 1 end\n", "(a...b).to_a", unwrap)).to(eq([1]))
      expect(writable("x && (a...b).to_a ? 1 : 2\n", "(a...b).to_a", unwrap)).to(eq([1]))
      expect(writable("x = (a...b).to_a\n", "(a...b).to_a", unwrap)).to(eq([0, 1]))
    end

    it "drops a variant that leaves a range literal tested inside it" do
      unlink = [{ "type" => "drop_receiver_link" }, { "type" => "return_nil" }]
      expect(writable("!(a...b).cover?(a)\n", "!(a...b).cover?(a)", unlink)).to(eq([1]))
    end

    it "keeps what it can't render", :aggregate_failures do
      expect(writable("if (a...b).to_a then 1 end\n", "(a...b).to_a", [{ "type" => "unknown" }])).to(eq([0]))
      expect(writable("if (a...b).to_a then 1 end\n", "(a...b).to_a then", unwrap)).to(eq([0, 1]))
      expect(writable("if (a...b).to_a then 1 end\n/\\xff/\n", "(a...b).to_a", unwrap)).to(eq([0, 1]))
    end
  end
end
