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
      program = <<~RUBY
        Baked = Data.define(:v) do
          def self.build(v, flag: false)
            new(v: flag)
          end
        end
      RUBY
      catalog = selected(%w[boolean_literal], program)
      [
        program,
        described_class.new(catalog).bake(
          "x.rb", program, catalog.points.find { |x| x.original_source == "false" }.mutants.first.id
        )
      ]
    end

    it "reopens a bound Data/Struct class so held references see the baked mutation", :aggregate_failures do
      stub_const("Baked", nil)
      program, baked = data
      expect(baked).to(include("const_defined?(:Baked, false)"))
      captured = TOPLEVEL_BINDING.eval(program).tap { TOPLEVEL_BINDING.eval(baked) }
      expect([Object.const_get(:Baked).equal?(captured), captured.build(1).v]).to(eq([true, true]))
    end

    # An emptied segment leaves an empty str in a dstr, which unparser couldn't
    # round-trip. The guarded path never hits this.
    def prune(program, keys, needle)
      catalog = selected(keys, program)
      described_class.new(catalog).bake(
        "x.rb", program, catalog.points.find { |point| point.original_source == needle }.mutants.first.id
      )
    end

    it "prunes an emptied leading segment of an interpolated string", :aggregate_failures do
      baked = prune("def m(x)\n  \"prefix \#{x}\"\nend\n", %w[string_literal], "prefix ")
      expect { Kimera::Scribe.parse(baked) }.not_to(raise_error)
      expect(baked).to(include("\"\#{x}\""))
      mod = Module.new.tap { |m| m.module_eval(baked) }
      expect(mod.instance_method(:m).bind_call(Object.new.extend(mod), "v")).to(eq("v"))
    end

    it "prunes an emptied trailing segment, keeping the interpolation", :aggregate_failures do
      baked = prune("def m(x)\n  \"\#{x} suffix\"\nend\n", %w[string_literal], " suffix")
      expect { Kimera::Scribe.parse(baked) }.not_to(raise_error)
      expect(baked).to(include("\"\#{x}\""))
    end

    it "keeps non-empty segments when pruning an emptied one" do
      baked = prune("def m(x)\n  \"a \#{x} b\"\nend\n", %w[string_literal], "a ")
      expect(baked).to(include("\"\#{x} b\""))
    end

    it "collapses a juxtaposed pair to the surviving plain string", :aggregate_failures do
      # Unparser rejected a dstr with a lone str child.
      baked = prune("def m\n  \"a \" \"b\"\nend\n", %w[string_literal], '"a "')
      expect(baked).to(include('"b"'))
      expect(baked).not_to(include('"a "'))
    end

    it "collapses a fully emptied juxtaposition to an empty string literal" do
      program = "def m\n  \"\" \"b\"\nend\n"
      catalog = selected(%w[string_literal], program)
      segment = catalog.points.find { |p| p.original_source == '"b"' }
      baked = described_class.new(catalog).bake("x.rb", program, segment.mutants.first.id)
      expect(baked).to(include('""'))
    end

    it "keeps an empty-string argument outside any interpolated literal" do
      program = "def m(a, b)\n  q(\"\", a > b)\nend\n"
      catalog = build(program)
      mutant = catalog.each.find { |m, _p| m.label == "> => <" }.first
      baked = described_class.new(catalog).bake("x.rb", program, mutant.id)
      expect(baked).to(include('q("", a < b)'))
    end

    it "leaves a plain xstr untouched by pruning" do
      # xstr interpolates, so pruning could degrade it to a plain str.
      program = "def m(a, b)\n  [`ls`, a > b]\nend\n"
      catalog = build(program)
      mutant = catalog.each.find { |m, _p| m.label == "> => <" }.first
      baked = described_class.new(catalog).bake("x.rb", program, mutant.id)
      expect(baked).to(include("[`ls`, a < b]"))
    end

    # unparser 0.9 raised on the array endpoint, so every mutant of the file
    # failed to bake.
    it "bakes a file with an array range endpoint" do
      program = "def m(a, b)\n  r = ([a, a]...a)\n  a > b\nend\n"
      catalog = build(program)
      mutant = catalog.each.find { |m, _p| m.label == "> => <" }.first
      expect(described_class.new(catalog).bake("x.rb", program, mutant.id)).to(include("r = ([a, a]...a)", "a < b"))
    end

    # unparser wrote an interpolation only if it read back as the same tree,
    # which an endpoint in parentheses did not.
    it "bakes a file interpolating a range with an array endpoint" do
      program = "def m(a, b)\n  \"x\#{([a]...[b]).size}y\"\n  a > b\nend\n"
      catalog = build(program)
      mutant = catalog.each.find { |m, _p| m.label == "> => <" }.first
      expect(described_class.new(catalog).bake("x.rb", program, mutant.id)).to(include("([a]...[b]).size", "a < b"))
    end

    # The swapped connective binds more loosely than the && around it.
    it "bakes a swapped connective with the grouping it had", :aggregate_failures do
      program = "def m(p, q, r)\n  x = p && q && r\nend\n"
      baked = prune(program, %w[boolean_connective], "p && q")
      expect(baked).to(include("x = (p || q) && r"))
      mod = Module.new.tap { |m| m.module_eval(baked) }
      expect(mod.instance_method(:m).bind_call(Object.new.extend(mod), true, nil, false)).to(be(false))
    end

    # unparser 0.9 wrote `-(0.succ)` as `-0.succ`, which Ruby reads as
    # `(-0).succ`, and `(-1) ** 2` as `-1 ** 2`, which is `-(1 ** 2)`. Inside a
    # string the parentheses must be in the tree, or the interpolation is
    # unwritable. A bake splices the literal alone, parenthesised where Ruby
    # would otherwise read it as part of the minus; across lines nothing else
    # keeps the lines after it.
    {
      "a minus over a chain rooted at the literal" => ["--1.succ", "-1", "-1 => 0", "-(0).succ", -1],
      "a literal raised to a power" => ["0 ** 2", "0", "0 => -1", "(-1) ** 2", 1],
      "a power across lines" => ["0 **\n    2", "0", "0 => -1", "(-1) **\n    2", 1],
      "a minus over a chain in an interpolation" => ["\"x\#{--1.succ}\"", "-1", "-1 => 0", "\"x\#{-(0).succ}\"", "x-1"],
      "a power in an interpolation" => ["\"x\#{0 ** 2}\"", "0", "0 => -1", "\"x\#{(-1) ** 2}\"", "x1"]
    }.each do |shape, (body, needle, label, written, value)|
      it "bakes a literal mutant under #{shape} as the program it names", :aggregate_failures do
        program = "def m\n  #{body}\nend\n"
        catalog = selected(%w[numeric_literal], program)
        mutant = catalog.points.find { |p| p.original_source == needle }.mutants.find { |m| m.label == label }
        baked = described_class.new(catalog).bake("x.rb", program, mutant.id)
        expect([baked.include?(written), Object.new.extend(Module.new.tap { |mod| mod.module_eval(baked) }).m])
          .to(eq([true, value]))
      end
    end

    # Prism sees a literal -1 inside `--1`, and kimera bakes the tree it
    # scans, so the bake reaches that literal (the parser gem folded it away).
    it "bakes the literal inside `--1`" do
      program = "def m\n  --1\nend\n"
      catalog = selected(%w[numeric_literal], program)
      mutant = catalog.points.find { |p| p.original_source == "-1" }.mutants.first
      baked = described_class.new(catalog).bake("x.rb", program, mutant.id)
      expect(Object.new.extend(Module.new.tap { |mod| mod.module_eval(baked) }).m).to(eq(-mutant.directive["value"]))
    end

    it "raises Unbakeable for a point with no node of its kind where it was scanned" do
      program = "def m\n  1\nend\n"
      catalog = selected(%w[numeric_literal], program)
      point = catalog.points.first
      allow(point).to(receive(:node_type).and_return("float_node"))
      expect { described_class.new(catalog).bake("x.rb", program, point.ids.first) }.to(
        raise_error(described_class::Unbakeable, Kimera::Overlay::FileWeave::UNMATCHED)
      )
    end

    it "bakes a file with a string escape that is invalid UTF-8" do
      program = "def scaled(size, data) = data.start_with?(\"\\xFF\\xD8\".b) ? size * 2 : size\n"
      catalog = selected(%w[arithmetic], program)
      baked = described_class.new(catalog).bake("x.rb", program, catalog.each.first.first.id)
      expect(baked).to(include('data.start_with?("\xFF\xD8".b)', "size / 2"))
    end

    # When the whole file can't be written, a warm run splices it per method,
    # so a bake writes the point's method alone.
    describe "in a file kimera can't write whole" do
      let(:program) do
        <<~'RUBY'
          module Sniffer
            LIMIT = 3
            Check = ->(value) { value > LIMIT }
            Size = Data.define(:x) do
              def big? = x > LIMIT
            end

            def self.banner(size)
              return "" if size < LIMIT
              <<~TEXT
                \xFF
                end
              TEXT
            end

            def self.scaled(size) = size * LIMIT
          end
        RUBY
      end
      let(:catalog) { selected(%w[arithmetic comparison], program) }

      # Kimera writes no tree but a method, and not the method named banner.
      def unwritable(method = nil)
        allow(Kimera::Scribe).to(receive(:new).and_wrap_original) do |original, node, *place|
          raise(RuntimeError, "unwritable") unless node.type == :def_node && node.name != :banner
          method ? instance_double(Kimera::Scribe, text: method, joined: nil) : original.call(node, *place)
        end
      end

      def bake(needle)
        point = catalog.points.find { |p| p.original_source == needle }
        synth = described_class.new(catalog)
        unwritable
        synth.bake("x.rb", program, point.mutants.first.id)
      end

      it "writes the method that holds the point and keeps the rest verbatim", :aggregate_failures do
        baked = bake("size * LIMIT")
        expect(baked).to(end_with(program.lines.drop(4).join.sub(" = size * LIMIT", "; size / LIMIT; end")))
        expect(Prism.parse(baked)).to(be_success)
      end

      # Re-evaluating `Size = Data.define do` would make a second class.
      it "reopens a value object around the method it writes", :aggregate_failures do
        baked = bake("x > LIMIT")
        expect(baked).to(include("Size = ((is_a?(::Module) ? self : ::Object).const_defined?(:Size, false)"))
        expect(baked).to(include("def big?; x >= LIMIT; end", "    \\xFF\n"))
      end

      it "raises Unbakeable for a point in the method it can't write, or in none", :aggregate_failures do
        message = /\Akimera could not write its bake \(RuntimeError: unwritable\)/
        expect { bake("size < LIMIT") }.to(raise_error(described_class::Unbakeable, message))
        expect { bake("value > LIMIT") }.to(raise_error(described_class::Unbakeable, message))
      end

      it "raises Unbakeable when the spliced method would not parse" do
        point = catalog.points.find { |p| p.original_source == "size * LIMIT" }
        synth = described_class.new(catalog)
        unwritable("def broken(")
        expect { synth.bake("x.rb", program, point.mutants.first.id) }
          .to(raise_error(described_class::Unbakeable, /could not write its bake/))
      end
    end

    it "raises Unbakeable, naming the failure, when kimera can't write the bake" do
      mutant = registry.each.first.first
      allow(Kimera::Scribe).to(receive(:new).and_raise(KeyError, "key not found: :lvar"))
      expect { synth.bake("x.rb", source, mutant.id) }.to(
        raise_error(described_class::Unbakeable, "kimera could not write its bake (KeyError: key not found: :lvar)")
      )
    end
  end

  # R6B4-M1..M3: a bake written whole, file or method, must read back as the
  # mutant meant.
  describe "a whole write that reads back as another program" do
    let(:source) { "def m(a, b)\n  a > b\nend\n" }
    let(:registry) { build(source) }

    it "is refused, file and method alike" do
      allow(Kimera::BakeSplice).to(receive(:new).and_return(instance_double(Kimera::BakeSplice, source: nil)))
      allow(Kimera::Readback).to(receive(:new).and_return(instance_double(Kimera::Readback, faithful?: false)))
      mutant = registry.each.find { |m, _p| m.label == "> => <" }.first
      expect { described_class.new(registry).bake("x.rb", source, mutant.id) }
        .to(raise_error(described_class::Unbakeable, /reads back as another program/))
    end
  end

  # R6B4-M5: since batch 3's line guard refused every bake that changes a line
  # outside the mutation, no element of a multi-line %i/%w literal could be
  # baked: the writer put the whole array on one line.
  describe "an element of a word list across lines" do
    let(:source) do
      <<~RUBY
        class Fields
          def names
            %i[
              type
              path
            ]
          end

          def labels
            %w[
              Type
              Path
            ]
          end
        end
      RUBY
    end
    let(:registry) { selected(%w[symbol_literal string_literal], source) }

    def baked(label)
      id = registry.each.find { |mutant, _| mutant.label == label }.first.id
      described_class.new(registry).bake("x.rb", source, id)
    end

    def changed(label) = source.lines.zip(baked(label).lines).each_with_index.reject { |(was, now), _| was == now }

    it "writes a word in place, changing its own line only" do
      expect(changed(":type => :type__kimera__")).to(eq([[["      type\n", "      type__kimera__\n"], 3]]))
    end

    it "writes an emptied word as the array, inside the literal's own lines", :aggregate_failures do
      expect(changed('"Type" => ""').map(&:last)).to(all(be_between(9, 12)))
      expect(Module.new.tap { it.module_eval(baked('"Type" => ""')) }::Fields.new.labels).to(eq(["", "Path"]))
    end
  end
end
