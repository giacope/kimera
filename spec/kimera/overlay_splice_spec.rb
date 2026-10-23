# frozen_string_literal: true

require "kimera/registry/builder"
require "kimera/synthesis/overlay"

# Overlays and bakes are spliced into the original source: only rewritten
# spans change, so every line, comment, magic comment and `__END__` section
# outside them stays where it was.
RSpec.describe(Kimera::Overlay) do
  def scan(source, keys)
    Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: keys)).source(source, file: "x.rb")
  end

  def bake(source, keys, label)
    catalog = scan(source, keys)
    mutant = catalog.each.find { |m, _| m.label == label }&.first
    described_class.new(catalog).bake("x.rb", source, mutant.id)
  end

  def woven(source, keys) = [described_class.new(registry = scan(source, keys)).synthesize("x.rb", source), registry]

  def changed(text, source)
    text.lines.zip(source.lines).each_with_index.reject { |(a, b), _| a == b }.map { |_, i| i + 1 }
  end

  def runtime = "::Kimera::RUNTIME"

  def loaded(text) = Object.new.extend(Module.new.tap { |mod| mod.module_eval(text) })

  describe "#bake" do
    let(:source) do
      "# Copyright header\n# frozen-string-literal: true\n\ndef pick(a, b) # keep me\n  " \
        "a > b ? \"x\".dup : \"y\"\nend\n__END__\ndata\n"
    end

    it "changes only the rewritten span, keeping comments and `__END__`", :aggregate_failures do
      baked = bake(source, %w[comparison], "> => >=")
      expect(baked).to(eq(source.sub("a > b", "a >= b")))
      expect(changed(baked, source)).to(eq([5]))
    end

    it "keeps a literal frozen under a hyphenated magic comment after a header" do
      baked = bake(source, %w[method_unwrap], "delete .dup")
      expect(loaded(baked).pick(2, 1).frozen?).to(be(true))
    end

    it "pads a shorter rewrite to the lines it replaces" do
      program = "def m(list)\n  list.each do |item|\n    puts(item)\n  end\n  :done\nend\n"
      baked = bake(program, %w[statement_deletion], "delete `list.each do |item|`")
      expect([baked.lines.size, baked.lines.last(2)]).to(eq([6, ["  :done\n", "end\n"]]))
    end

    it "groups a rewrite Ruby would otherwise read as part of its neighbour" do
      program = "def m(a)\n  a * 2 + 1\nend\n"
      expect(loaded(bake(program, %w[arithmetic], "+ => -")).m(3)).to(eq(5))
    end

    it "writes a rewrite of several statements on the span's line" do
      program = "class Shown\n  def one = 1\n  def two = 2\nend\n"
      expect(
        bake(
          program, %w[visibility],
          "public => private (one)"
        )
      ).to(include("def one = 1; private(:one)\n  def two"))
    end

    it "writes an argument list emptied beside a block argument without a stray comma" do
      program = "def m(list, &test) = list.select(list, &test)\n"
      expect(bake(program, %w[argument_drop], "drop arg `list`")).to(include("list.select(&test)"))
    end

    it "writes a regexp part from its mutated value" do
      program = "def key?(name, prefix) = name.match?(/\\A\#{prefix}_id\\z/)\n"
      baked = bake(program, %w[string_literal], "\"\\\\A\" => \"\"")
      expect(
        [
          baked,
          loaded(baked).key?("xuser_id", "user")
        ]
      ).to(eq(["def key?(name, prefix) = name.match?(/\#{\"\"}\#{prefix}_id\\z/)\n", true]))
    end

    it "reopens a factory-built constant around a spliced method" do
      program = "Pair = Struct.new(:x) do\n  def big? = x > 1\nend\n"
      expect(
        bake(
          program, %w[comparison],
          "> => >="
        )
      ).to(start_with("Pair = ((is_a?(::Module) ? self : ::Object).const_defined?"))
    end

    it "reports a mutant that reads as the original as unmutatable" do
      catalog = scan(source, %w[comparison])
      mutant = catalog.each.first.first
      allow(Kimera::Rewrite::Directive).to(
        receive(:new).and_wrap_original do |_, _|
          instance_double(Kimera::Rewrite::Directive, apply: nil)
        end
      )
      allow(Kimera::Guardrail).to(receive(:new).and_wrap_original) { |build, *arguments| build.call(*arguments).tap { |rail| allow(rail).to(receive(:changes).and_return([])) } }
      expect { described_class.new(catalog).bake("x.rb", source, mutant.id) }
        .to(raise_error(described_class::Unbakeable, "kimera could not write it (the mutant reads as the original)"))
    end

    it "reports a bake that does not parse as unmutatable" do
      catalog = scan(source, %w[comparison])
      allow(Kimera::BakeSplice).to(receive(:new).and_return(instance_double(Kimera::BakeSplice, source: "def (")))
      expect { described_class.new(catalog).bake("x.rb", source, catalog.each.first.first.id) }
        .to(raise_error(described_class::Unbakeable, "kimera could not write it (what it wrote does not parse)"))
    end
  end

  describe "#synthesize" do
    let(:source) do
      "# frozen_string_literal: true\n\nclass Gate\n  # Opens above the limit.\n  def open?(n, limit = 3)\n    " \
        "n > limit && n.even?\n  end\n\n  def line = __LINE__\nend\n__END__\nkept\n"
    end

    it "keeps every line where it was and the original as written", :aggregate_failures do
      result, = woven(source, %w[comparison boolean_connective default_argument])
      expect(result.source.lines.size).to(eq(source.lines.size))
      expect(changed(result.source, source)).to(eq([5, 6]))
      expect(result.source).to(include("::Kimera::RUNTIME.active?(3) || ::Kimera::RUNTIME.active?(4)) ? (n > limit) :"))
    end

    def flip(registry, label, &) = Kimera::RUNTIME.during(registry.each.find { |m, _| m.label == label }.first.id, &)

    it "behaves as the original with no mutant on and as each mutant with it on", :aggregate_failures do
      result, registry = woven(source, %w[comparison default_argument])
      gate = Module.new.tap { |mod| mod.module_eval(result.source, "x.rb", 1) }::Gate.new
      expect([gate.open?(4), gate.open?(3), gate.line]).to(eq([true, false, 9]))
      expect(flip(registry, "> => >=") { gate.open?(4, 4) }).to(be(true))
      expect { flip(registry, "default => required (limit)") { gate.open?(4) } }.to(raise_error(ArgumentError, /limit/))
    end

    it "guards a named-capture regexp with its whole match, so the capture still binds" do
      program = "def number(s)\n  if /(?<num>\\d+)/ =~ s then num.to_i end\nend\n"
      result, = woven(program, %w[regexp_quantifier regexp_anchor])
      expect([loaded(result.source).number("x21"), result.source]).to(match([21, include("? (/(?<num>\\d+)/ =~ s) :")]))
    end

    it "writes a visibility mutant's probe and registration on the method's own lines", :aggregate_failures do
      program = "class Probed\n  def one(a)\n    a\n  end\n  def two = 2\nend\n"
      written = woven(program, %w[visibility]).first.source
      expect(written.lines.size).to(eq(program.lines.size))
      expect(written).to(include("def one(a); #{runtime}.active?(1)\n", "  end; #{runtime}.privatize(1, self, :one)\n"))
      expect(written).to(include("def two = (#{runtime}.active?(2); 2); #{runtime}.privatize(2, self, :two)"))
    end

    it "writes a definition whole when a point in it can't be guarded where it stands", :aggregate_failures do
      program = "def safe(x)\n  x.call\nrescue ArgumentError\n  x > 1\nend\n\ndef other(y) = y > 2\n"
      result, registry = woven(program, %w[rescue_clause comparison])
      expect(result.mutant_ids).to(match_array(registry.points.flat_map(&:ids)))
      expect(result.source).to(
        end_with(
          "\n\ndef other(y) = (!(::Kimera::RUNTIME.active?(4) || ::Kimera::RUNTIME.active?(5)) ? (y > 2) : " \
            "::Kimera::RUNTIME.active?(4) ? (y >= 2) : (y < 2))\n"
        )
      )
    end

    it "writes the whole file when such a point stands outside every definition" do
      program = "CHECK = ->(x) do\n  begin\n    x.call\n  rescue ArgumentError\n    x > 1\n  end\nend\n"
      result, registry = woven(program, %w[rescue_clause comparison])
      expect([result.mutant_ids.size, result.source]).to(match([registry.count, include("if ::Kimera::RUNTIME.active?(1)\n")]))
    end

    it "writes a definition whole when an alternative would cross a heredoc's lines", :aggregate_failures do
      program = "def m(a)\n  a.push([1,\n    2], <<~TEXT)\n    body\n  TEXT\nend\n"
      result, = woven(program, %w[argument_drop])
      expect(result.source).to(start_with("def m(a)\n  if ::Kimera::RUNTIME.active?(1)\n"))
      expect(loaded(result.source).m([])).to(eq([[1, 2], "body\n"]))
    end
  end
end
