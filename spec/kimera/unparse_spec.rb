# frozen_string_literal: true

require "kimera/support/unparse"

# Minitest turns on deprecation warnings when it loads, and parser (under
# unparser) trips them on every synthesis, flooding the run's stderr.
RSpec.describe(Kimera::Unparse) do
  it "round-trips source without letting unparser's warnings through", :aggregate_failures do
    allow(Unparser).to(receive(:parse).and_wrap_original { |original, source| warn("noise") || original.call(source) })
    allow(Unparser).to(receive(:unparse).and_wrap_original { |original, node| warn("noise") || original.call(node) })
    expect { expect(described_class.unparse(described_class.parse("a > b"))).to(eq("a > b")) }.not_to(output.to_stderr)
  end

  # unparser 0.9 only tracked locals from assignments and method parameters, so a
  # string interpolating any other local failed its round-trip check and took the
  # whole file down with it.
  describe(Kimera::Unparse::Binders) do
    def reemit(source) = Kimera::Unparse.unparse(Kimera::Unparse.parse(source))

    {
      "a case/in binding" => "def bid(value) = (case value; in chosen then \"\#{chosen}\"; end)",
      "an array pattern binding" => "def bid(v) = (case v; in [:parsed, chosen] then [\"\#{chosen}\", chosen]; end)",
      "a hash pattern binding" => "def bid(value) = (case value; in {chosen:} then \"\#{chosen}\"; end)",
      "a splat pattern binding" => "def bid(value) = (case value; in [*chosen] then \"\#{chosen}\"; end)",
      "a rightward assignment" => "def bid(value) = (value => chosen; \"\#{chosen}\")",
      "a block parameter" => "def bid(&chosen) = \"\#{chosen}\"",
      "a regexp named capture" => "def bid(value) = (/(?<chosen>.)/ =~ value; \"\#{chosen}\")"
    }.each do |binder, source|
      it "round-trips a string interpolating #{binder}" do
        expect(reemit(source)).to(include("\"\#{chosen}\""))
      end
    end

    it "binds no name for an anonymous block parameter", :aggregate_failures do
      anonymous = Kimera::Unparse.parse("def bid(&) = forward(&)").children[1].children.first
      expect(described_class.names(anonymous)).to(eq([]))
      expect(reemit("def bid(&) = forward(&)")).to(eq("def bid(&)\n  forward(&)\nend"))
    end

    # Under /x, a (?<name>) inside a comment names nothing, so the read stays a call.
    it "binds only the captures an extended regexp really names", :aggregate_failures do
      node = Kimera::Unparse.parse("/(?<real>.) # (?<fake>.)\n/x =~ value")
      expect(described_class.names(node)).to(eq([:real]))
      plain = Kimera::Unparse.parse("/(?<real>.) # (?<also>.)/ =~ value")
      expect(described_class.names(plain)).to(eq(%i[real also]))
    end

    it "binds nothing for nodes that bind nothing", :aggregate_failures do
      expect(described_class.names(Kimera::Unparse.parse("chosen = 1"))).to(eq([]))
      expect(described_class.names(Kimera::Unparse.parse("value"))).to(eq([]))
    end
  end

  # unparser 0.9 writes an array range endpoint as a %w/%i literal.
  describe(Kimera::Unparse::RangeEndpoints) do
    def reemit(source) = Kimera::Unparse.unparse(Kimera::Unparse.parse(source))

    {
      "([a, a]...a)" => "(([a, a])...a)\n", "(0...[a, a])" => "(0...([a, a]))\n",
      "[1, 2]..3" => "([1, 2])..3", "[1]..[2]" => "([1])..([2])", "[1]..nil" => "([1])..nil",
      "[1]..;" => "([1])..", "..[1]" => "..([1])", "[\"a b\", \"c]\"]..d" => "([\"a b\", \"c]\"])..d"
    }.each do |source, written|
      it "writes `#{source}` with its array endpoint in parentheses" do
        expect(reemit(source)).to(eq(written))
      end
    end

    it "leaves other endpoints as unparser writes them", :aggregate_failures do
      expect(reemit("1..2")).to(eq("1..2"))
      expect(reemit("..2")).to(eq("..2"))
      expect(reemit("a...")).to(eq("a..."))
      expect(reemit("0...(1..2)")).to(eq("0...(1..2)"))
    end
  end
end
