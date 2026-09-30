# frozen_string_literal: true

require "kimera/registry/builder"
require "kimera/synthesis/overlay"

# The reload fallback: one mutation baked into source, unguarded.
RSpec.describe(Kimera::Overlay) do
  def build(source, file: "x.rb")
    Kimera::RegistryScan.new.source(source, file: file)
  end

  def selected(keys, source, file: "x.rb")
    Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: keys)).source(source, file: file)
  end

  describe "#bake" do
    let(:source) { "def m(a, b)\n  a > b\nend\n" }
    let(:registry) { build(source) }
    let(:synth) { described_class.new(registry) }

    it "applies exactly the requested mutant directly into the source", :aggregate_failures do
      mutant = registry.each.find { |m, _p| m.label == "> => <" }.first
      baked = synth.bake("x.rb", source, mutant.id)
      expect(baked).to(include("a < b"))
      expect(baked).not_to(include("active?")) # no guard, unlike synthesize
    end

    it "applies the boundary variant when that mutant is chosen" do
      mutant = registry.each.find { |m, _p| m.label == "> => >=" }.first
      expect(synth.bake("x.rb", source, mutant.id)).to(include("a >= b"))
    end

    it "returns the source verbatim for an unknown mutant id" do
      expect(synth.bake("x.rb", source, 999_999)).to(eq(source))
    end

    # Rebinding the constant would leave described_class on the original class,
    # so every baked mutant would falsely survive.
    def data
      src = <<~RUBY
        Baked = Data.define(:v) do
          def self.build(v, flag: false)
            new(v: flag)
          end
        end
      RUBY
      catalog = selected(%w[boolean_literal], src)
      [
        src,
        described_class.new(catalog).bake(
          "x.rb", src, catalog.points.find { |x| x.original_source == "false" }.mutants.first.id
        )
      ]
    end

    it "reopens a bound Data/Struct class so held references see the baked mutation", :aggregate_failures do
      stub_const("Baked", nil)
      src, baked = data
      expect(baked).to(include("const_defined?(:Baked, false)"))
      captured = TOPLEVEL_BINDING.eval(src).tap { TOPLEVEL_BINDING.eval(baked) }
      expect([Object.const_get(:Baked).equal?(captured), captured.build(1).v]).to(eq([true, true]))
    end

    # An emptied segment leaves an empty str in a dstr, which unparser can't
    # round-trip. The guarded path never hits this.
    def prune(src, keys, needle)
      catalog = selected(keys, src)
      described_class.new(catalog).bake(
        "x.rb", src, catalog.points.find { |point| point.original_source == needle }.mutants.first.id
      )
    end

    it "prunes an emptied leading segment of an interpolated string", :aggregate_failures do
      baked = prune("def m(x)\n  \"prefix \#{x}\"\nend\n", %w[string_literal], "prefix ")
      expect { Unparser.parse(baked) }.not_to(raise_error)
      expect(baked).to(include('"#{x}"'))
      mod = Module.new.tap { |m| m.module_eval(baked) }
      expect(mod.instance_method(:m).bind_call(Object.new.extend(mod), "v")).to(eq("v"))
    end

    it "prunes an emptied trailing segment, keeping the interpolation", :aggregate_failures do
      baked = prune("def m(x)\n  \"\#{x} suffix\"\nend\n", %w[string_literal], " suffix")
      expect { Unparser.parse(baked) }.not_to(raise_error)
      expect(baked).to(include('"#{x}"'))
    end

    it "keeps non-empty segments when pruning an emptied one" do
      baked = prune("def m(x)\n  \"a \#{x} b\"\nend\n", %w[string_literal], "a ")
      expect(baked).to(include('"#{x} b"'))
    end

    it "collapses a juxtaposed pair to the surviving plain string", :aggregate_failures do
      # Unparser rejects a dstr with a lone str child.
      baked = prune("def m\n  \"a \" \"b\"\nend\n", %w[string_literal], '"a "')
      expect(baked).to(include('"b"'))
      expect(baked).not_to(include('"a "'))
    end

    it "collapses a fully emptied juxtaposition to an empty string literal" do
      src = "def m\n  \"\" \"b\"\nend\n"
      catalog = selected(%w[string_literal], src)
      segment = catalog.points.find { |p| p.original_source == '"b"' }
      baked = described_class.new(catalog).bake("x.rb", src, segment.mutants.first.id)
      expect(baked).to(include('""'))
    end

    it "keeps an empty-string argument outside any interpolated literal" do
      src = "def m(a, b)\n  q(\"\", a > b)\nend\n"
      catalog = build(src)
      mutant = catalog.each.find { |m, _p| m.label == "> => <" }.first
      baked = described_class.new(catalog).bake("x.rb", src, mutant.id)
      expect(baked).to(include('q("", a < b)'))
    end

    it "leaves a plain xstr untouched by pruning" do
      # xstr interpolates, so pruning could degrade it to a plain str.
      src = "def m(a, b)\n  [`ls`, a > b]\nend\n"
      catalog = build(src)
      mutant = catalog.each.find { |m, _p| m.label == "> => <" }.first
      baked = described_class.new(catalog).bake("x.rb", src, mutant.id)
      expect(baked).to(include("[`ls`, a < b]"))
    end

    # unparser 0.9 raised on the array endpoint, so every mutant of the file
    # failed to bake.
    it "bakes a file with an array range endpoint" do
      src = "def m(a, b)\n  r = ([a, a]...a)\n  a > b\nend\n"
      catalog = build(src)
      mutant = catalog.each.find { |m, _p| m.label == "> => <" }.first
      expect(described_class.new(catalog).bake("x.rb", src, mutant.id)).to(include("r = ([a, a]...a)", "a < b"))
    end

    # unparser writes an interpolation only if it reads back as the same tree,
    # which an endpoint in parentheses did not.
    it "bakes a file interpolating a range with an array endpoint" do
      src = "def m(a, b)\n  \"x\#{([a]...[b]).size}y\"\n  a > b\nend\n"
      catalog = build(src)
      mutant = catalog.each.find { |m, _p| m.label == "> => <" }.first
      expect(described_class.new(catalog).bake("x.rb", src, mutant.id)).to(include("([a]...[b]).size", "a < b"))
    end

    # The swapped connective binds more loosely than the && around it.
    it "bakes a swapped connective with the grouping it had", :aggregate_failures do
      src = "def m(p, q, r)\n  x = p && q && r\nend\n"
      baked = prune(src, %w[boolean_connective], "p && q")
      expect(baked).to(include("x = (p || q) && r"))
      mod = Module.new.tap { |m| m.module_eval(baked) }
      expect(mod.instance_method(:m).bind_call(Object.new.extend(mod), true, nil, false)).to(be(false))
    end

    # unparser 0.9 wrote `-(0.succ)` as `-0.succ`, which Ruby reads as
    # `(-0).succ`, and `(-1) ** 2` as `-1 ** 2`, which is `-(1 ** 2)`. Inside a
    # string the parentheses must be in the tree, or the interpolation is
    # unwritable.
    {
      "a minus over a chain rooted at the literal" => ["--1.succ", "-1", "-1 => 0", "-(0.succ)", -1],
      "a literal raised to a power" => ["0 ** 2", "0", "0 => -1", "(-1) ** 2", 1],
      "a minus over a chain in an interpolation" => ["\"x\#{--1.succ}\"", "-1", "-1 => 0", "\"x\#{-(0.succ)}\"", "x-1"],
      "a power in an interpolation" => ["\"x\#{0 ** 2}\"", "0", "0 => -1", "\"x\#{(-1) ** 2}\"", "x1"]
    }.each do |shape, (body, needle, label, written, value)|
      it "bakes a literal mutant under #{shape} as the program it names", :aggregate_failures do
        src = "def m\n  #{body}\nend\n"
        catalog = selected(%w[numeric_literal], src)
        mutant = catalog.points.find { |p| p.original_source == needle }.mutants.find { |m| m.label == label }
        baked = described_class.new(catalog).bake("x.rb", src, mutant.id)
        expect(baked).to(include(written))
        expect(Object.new.extend(Module.new.tap { |mod| mod.module_eval(baked) }).m).to(eq(value))
      end
    end

    # Prism sees a literal -1 inside `--1`; the parser folds both minuses into
    # one literal. The bake returned the file unchanged, a survivor with
    # --isolated where the warm run reports the point unmutatable.
    it "raises Unbakeable for a point the parser folds away, as the warm run reports it" do
      src = "def m\n  --1\nend\n"
      catalog = selected(%w[numeric_literal], src)
      mutant = catalog.points.find { |p| p.original_source == "-1" }.mutants.first
      expect { described_class.new(catalog).bake("x.rb", src, mutant.id) }.to(
        raise_error(described_class::Unbakeable, Kimera::Overlay::FileWeave::UNMATCHED)
      )
    end

    it "raises Unbakeable, naming the unparser failure, when unparser can't write the bake" do
      mutant = registry.each.first.first
      allow(Kimera::Unparse).to(receive(:unparse).and_raise(KeyError, "key not found: :lvar"))
      expect { synth.bake("x.rb", source, mutant.id) }.to(
        raise_error(described_class::Unbakeable, "unparser could not write its bake (KeyError: key not found: :lvar)")
      )
    end
  end
end
