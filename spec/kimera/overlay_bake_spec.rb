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
  end
end
