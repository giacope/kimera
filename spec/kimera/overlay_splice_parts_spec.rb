# frozen_string_literal: true

require "kimera/registry/builder"
require "kimera/synthesis/overlay"

# The spliced text for each shape of point.
RSpec.describe(Kimera::Overlay) do
  def scan(source, keys)
    Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: keys)).source(source, file: "x.rb")
  end

  def woven(source, keys) = described_class.new(scan(source, keys)).synthesize("x.rb", source).source

  def bake(source, keys, label)
    catalog = scan(source, keys)
    described_class.new(catalog).bake("x.rb", source, catalog.each.find { |m, _| m.label == label }.first.id)
  end

  def runtime = "::Kimera::RUNTIME.active?"

  describe "guards at the smallest expression a rewrite changes" do
    {
      ["def m(a)\n  if a\n    1\n  end\nend\n", %w[conditional]] => "  if (!(::Kimera::RUNTIME.active?(1) ||",
      [
        "def m(a) = a.b.c\n",
        %w[chain_link_deletion]
      ] => "def m(a) = (!(::Kimera::RUNTIME.active?(1)) ? (a.b) : (a)).c\n",
      ["def m = %w[a b]\n", %w[string_literal]] => "? (%w[a b]) : ::Kimera::RUNTIME.active?(1) ? ([\"\", \"b\"]) : ",
      [
        "def m = \"a\" \\\n  \"b\"\n",
        %w[string_literal]
      ] => "? (\"a\" \\\n  \"b\") : ::Kimera::RUNTIME.active?(1) ? (\"\" \"b\")",
      ["def m(a) = a.push(<<~T, a > 1)\n  x\nT\n", %w[comparison]] => "def m(a) = a.push(<<~T, (!(",
      [
        "def m(a)\n  a.push([1,\n    2], 3 > a)\nend\n",
        %w[argument_drop]
      ] => "(a.push(3 > a)) : (a.push([1, 2])))\n",
      ["def m(a)\n  a.push([1,\n    2], <<~T)\n    body\n  T\nend\n", %w[argument_drop]] =>
        "(a.push([1,\n    2], <<~T)) : ::Kimera::RUNTIME.active?(1) ? (a.push(\"body\\n\")) : " \
        "(a.push([1, 2])))\n    body\n",
      ["def m(l) = l.map { it > 0 }\n", %w[comparison]] => "l.map { (!(::Kimera::RUNTIME.active?(1) || " \
        "::Kimera::RUNTIME.active?(2)) ? (it > 0) : ::Kimera::RUNTIME.active?(1) ? (it >= 0) : (it < 0)) }\n",
      ["def m(a, b)\n  @a, @b = a, b\nend\n", %w[collection_literal]] =>
        "  (!(::Kimera::RUNTIME.active?(1)) ? (@a, @b = a, b) : (@a, @b = []))\n",
      ["def m(a)\n  x = *a, 1\nend\n", %w[collection_literal]] =>
        "  (!(::Kimera::RUNTIME.active?(1)) ? (x = *a, 1) : (x = []))\n",
      ["def m(x) = { \"\#{x}_a\": 1 }\n", %w[string_literal]] =>
        "def m(x) = (!(::Kimera::RUNTIME.active?(1)) ? ({ \"\#{x}_a\": 1 }) : ({ \"\#{x}\": 1 }))\n",
      ["def m = { \"plain\": :a }\n", %w[symbol_literal]] =>
        "def m = { \"plain\": (!(::Kimera::RUNTIME.active?(1)) ? (:a) : (:a__kimera__)) }\n",
      ["class Q\n  def t = true\nend\n", %w[visibility boolean_literal]] =>
        "  def t = (::Kimera::RUNTIME.active?(1); (!(::Kimera::RUNTIME.active?(2)) ? (true) : (false))); ::Kimera"
    }.each do |(source, keys), written|
      it "writes #{source.lines.first.strip} with #{keys.join(", ")} in place" do
        expect(woven(source, keys)).to(include(written))
      end
    end
  end

  describe "writes a definition whole, on its own lines, when a guard can't stand in place" do
    {
      ["def m(a)\n  a.call\nrescue ArgumentError\n  0\nend\n# kept\nLINE = __LINE__\n", %w[rescue_clause]] =>
        "def m(a); if ::Kimera::RUNTIME.active?(1); a.call; else; begin; a.call; rescue ArgumentError; 0; end; " \
        "end; \n\n\n\nend\n"
    }.each do |(source, keys), written|
      it "writes #{source.lines.first.strip} whole and keeps the rest", :aggregate_failures do
        expect(woven(source, keys)).to(start_with(written))
        expect(woven(source, keys)).to(end_with("# kept\nLINE = __LINE__\n"))
      end
    end
  end

  it "reopens a constant any factory builds from a block that defines methods" do
    expect(
      woven(
        "Opts = Options.new(:a) do\n  def big? = a > 1\nend\n",
        %w[comparison]
      )
    ).to(include("const_defined?(:Opts, false)"))
  end

  it "leaves a named capture's regexp unguarded when its definition is written whole", :aggregate_failures do
    source = "def number(s)\n  if /(?<num>\\d+)/ =~ s then num.to_i end\nrescue ArgumentError\n  0\nend\n"
    written = woven(source, %w[regexp_quantifier rescue_clause])
    expect([written, Object.new.extend(Module.new.tap { |mod| mod.module_eval(written) }).number("x21")])
      .to(match([start_with("def number(s); if ::Kimera::RUNTIME.active?("), 21]))
  end

  {
    "def m(a) = a > 1\n" => %w[comparison], "class V\n  def m(a) = a\nend\n" => %w[visibility]
  }.each do |source, keys|
    it "reports a #{keys.first} point whose node is gone as unmutatable", :aggregate_failures do
      catalog = scan(source, keys)
      allow(catalog.points.first).to(receive(:node_type).and_return("float_node"))
      result = described_class.new(catalog).synthesize("x.rb", source)
      expect([result.skipped_unsafe, catalog.points.first.unsafe_reason])
        .to(eq([catalog.points.first.ids, "unmutatable: #{Kimera::Overlay::FileWeave::UNMATCHED}"]))
    end
  end

  describe Kimera::Overlay::Stitch do
    def stitched(edits)
      weave = instance_double(Kimera::GuardSplice, rest: [], edits: edits, applied: [7])
      allow(Kimera::GuardSplice).to(receive(:new).and_return(weave))
      described_class.new("x.rb", Kimera::SourceMap.new("a = 1\n"), [], []).result
    end

    it "writes the edits of the guards it was given", :aggregate_failures do
      result = stitched([[4, 5, "2"]])
      expect([result.source, result.mutant_ids]).to(eq(["a = 2\n", [7]]))
    end

    it "writes nothing for edits that overlap, even ones whose text would parse" do
      expect(stitched([[4, 5, "2"], [4, 5, "3"]])).to(be_nil)
    end

    it "writes nothing whose text does not parse" do
      expect(stitched([[4, 5, "("]])).to(be_nil)
    end
  end

  describe "#bake" do
    {
      ["def m(v)\n  foo(\n    \"Ruby/\#{v}\",\n    2)\nend\n", %w[string_literal], "\"Ruby/\" => \"\""] =>
        "def m(v)\n  foo(\n    \"\#{v}\",\n    2)\nend\n",
      [
        "def m(list)\n  list.each do |item|\n    puts(item)\n  end\nend\n", %w[statement_deletion],
        "delete `list.each do |item|`"
      ] =>
        "def m(list)\n  ()\n\n\nend\n",
      ["def m(a)\n  puts(<<~T, a > 1)\n    body\n  T\nend\n", %w[argument_drop], "drop arg `a > 1`"] =>
        "def m(a)\n  puts(\"body\\n\")\nend\n\n\n",
      ["def m(a)\n  puts(<<~T, a > 1)\n    body\n  T\n  a\nend\n", %w[argument_drop], "drop arg `a > 1`"] =>
        "def m(a)\n  puts(\"body\\n\")\n  a\n\n\nend\n",
      [
        "def m(a)\n  x = begin\n    a.call\n    a.size\n  rescue ArgumentError\n    0\n  end\n  x\nend\n",
        %w[rescue_clause], "drop `rescue ArgumentError`"
      ] => "def m(a)\n  x = (a.call\n  a.size\n\n\n\n)\n  x\nend\n",
      ["def m(a)\n  if a # why\n    1\n  end\nend\n", %w[conditional], "condition => true"] =>
        "def m(a)\n  if true # why\n    1\n  end\nend\n"
    }.each do |(source, keys, label), baked|
      it "bakes #{label} as #{baked.inspect}" do
        expect(bake(source, keys, label)).to(eq(baked))
      end
    end
  end
end
