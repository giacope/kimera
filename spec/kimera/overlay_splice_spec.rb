# frozen_string_literal: true

require "kimera/registry/builder"
require "kimera/synthesis/overlay"

using PointFields

# Overlays and bakes are spliced into the original source: only rewritten
# spans change, so every line, comment, magic comment and `__END__` section
# outside them stays where it was.
RSpec.describe(Kimera::Overlay) do
  def scan(source, keys)
    Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: keys)).source(source, file: "x.rb")
  end

  def bake(source, keys, label)
    catalog = scan(source, keys)
    mutant = catalog.each.find { |m, _| m.to_s == label }&.first
    described_class.new(catalog).bake("x.rb", source, mutant.to_i)
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

    it "writes a deleted statement as `()`, which Ruby reads without a warning", :aggregate_failures do
      program = "def greet(log, name)\n  log.push(name)\n  name\nend\n"
      baked = bake(program, %w[statement_deletion], "delete `log.push(name)`")
      expect(baked).to(eq("def greet(log, name)\n  ()\n  name\nend\n"))
      expect(Prism.parse(baked).warnings).to(be_empty)
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

    # Dropping the only use of `_1` leaves a block that would take no
    # parameter, so the block's parameter is written out.
    it "names a numbered block's parameter when the bake drops its only use" do
      program = "def m(list) = list.map { foo(_1) > 2 }\n"
      expect(bake(program, %w[argument_drop], "drop arg `_1`"))
        .to(eq("def m(list) = list.map { |__kimera_1|; foo() > 2; }\n"))
    end

    it "reports a mutant that reads as the original as unmutatable" do
      catalog = scan(source, %w[comparison])
      mutant = catalog.each.first.first
      stub_const("Kimera::Guardrail", Class.new(Kimera::Guardrail) { def changes(*) = [] })
      expect { described_class.new(catalog).bake("x.rb", source, mutant.to_i) }
        .to(raise_error(described_class::Unbakeable, "kimera could not write it (the mutant reads as the original)"))
    end

    it "reports a bake that would change a line outside the mutation as unmutatable" do
      program = "def one = 1\n# two\ndef big?(x) = x > 1\n"
      catalog = scan(program, %w[comparison])
      splicing
      expect { described_class.new(catalog).bake("x.rb", program, catalog.each.first.first.to_i) }
        .to(
          raise_error(
            described_class::Unbakeable,
            "kimera could not write it (what it wrote changes or moves a line outside the mutation)"
          )
        )
    end

    it "reports a bake that does not parse as unmutatable" do
      catalog = scan(source, %w[comparison])
      splicing("def (")
      expect { described_class.new(catalog).bake("x.rb", source, catalog.each.first.first.to_i) }
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
      expect(result.to_s.lines.size).to(eq(source.lines.size))
      expect(changed(result.to_s, source)).to(eq([5, 6]))
      expect(result.to_s).to(include("::Kimera::RUNTIME.active?(3) || ::Kimera::RUNTIME.active?(4)) ? (n > limit) :"))
    end

    def flip(registry, label, &) = Kimera::RUNTIME.during(registry.each.find { |m, _| m.to_s == label }.first.to_i, &)

    it "behaves as the original with no mutant on and as each mutant with it on", :aggregate_failures do
      result, registry = woven(source, %w[comparison default_argument])
      gate = Module.new.tap { |mod| mod.module_eval(result.to_s, "x.rb", 1) }::Gate.new
      expect([gate.open?(4), gate.open?(3), gate.line]).to(eq([true, false, 9]))
      expect(flip(registry, "> => >=") { gate.open?(4, 4) }).to(be(true))
      expect { flip(registry, "default => required (limit)") { gate.open?(4) } }.to(raise_error(ArgumentError, /limit/))
    end

    it "guards a named-capture regexp with its whole match, so the capture still binds" do
      program = "def number(s)\n  if /(?<num>\\d+)/ =~ s then num.to_i end\nend\n"
      result, = woven(program, %w[regexp_quantifier regexp_anchor])
      expect([loaded(result.to_s).number("x21"), result.to_s]).to(match([21, include("? (/(?<num>\\d+)/ =~ s) :")]))
    end

    it "writes a visibility mutant's probe and registration on the method's own lines", :aggregate_failures do
      program = "class Probed\n  def one(a)\n    a\n  end\n  def two = 2\nend\n"
      written = woven(program, %w[visibility]).first.to_s
      expect(written.lines.size).to(eq(program.lines.size))
      expect(written).to(include("def one(a); #{runtime}.active?(1)\n", "  end; #{runtime}.privatize(1, self, :one)\n"))
      expect(written).to(include("def two = (#{runtime}.active?(2); 2); #{runtime}.privatize(2, self, :two)"))
    end

    it "writes a definition whole when a point in it can't be guarded where it stands", :aggregate_failures do
      program = "def safe(x)\n  x.call\nrescue ArgumentError\n  x > 1\nend\n\ndef other(y) = y > 2\n"
      result, registry = woven(program, %w[rescue_clause comparison])
      expect(result.to_h.fetch(:mutant_ids)).to(match_array(registry.to_a.flat_map(&:ids)))
      expect(result.to_s).to(
        end_with(
          "\n\ndef other(y) = (!(::Kimera::RUNTIME.active?(4) || ::Kimera::RUNTIME.active?(5)) ? (y > 2) : " \
            "::Kimera::RUNTIME.active?(4) ? (y >= 2) : (y < 2))\n"
        )
      )
    end

    # A point no guard can hold in place has its definition written whole.
    def whole! = unanchored

    # The method written whole holds every guard: a default argument's raise,
    # a visibility mutant's probe and registration.
    describe "a definition written whole" do
      let(:written) do
        whole!
        woven(
          "class Whole\n  def gated(flag, limit = 1); flag.call(limit); rescue TypeError; 0; end\nend\n",
          %w[rescue_clause default_argument visibility]
        )
      end

      def whole = Module.new.tap { |mod| mod.module_eval(written.first.to_s) }::Whole

      def id(label) = written.last.each.find { |mutant, _| mutant.to_s == label }.first.to_i

      it "keeps every mutant in it live" do
        expect(written.first.to_h.fetch(:mutant_ids)).to(match_array(written.last.to_a.flat_map(&:ids)))
      end

      it "raises for its default argument's mutant" do
        expect { Kimera::RUNTIME.during(id("default => required (limit)")) { whole.new.gated(nil) } }
          .to(raise_error(ArgumentError, "missing argument: limit"))
      end

      it "probes its visibility mutant and turns it private with it on", :aggregate_failures do
        hidden = id("public => private (gated)")
        held = whole
        expect(Kimera::RUNTIME.during(hidden) { held.private_method_defined?(:gated) }).to(be(true))
        expect(written.first.to_s).to(include("#{runtime}.active?(#{hidden}); nil; else; nil; end"))
      end
    end

    # R6B5-M2: the method's own `rescue` is guarded where it stands; every
    # other guard too, and no line of the method moves.
    describe "a definition with its own clause" do
      let(:program) do
        <<~RUBY
          class Kept
            def gated(f, n = 1)
              f.call(n)
            rescue TypeError
              [0, __LINE__]
            end
          end
        RUBY
      end
      let(:written) { woven(program, %w[rescue_clause default_argument visibility]) }

      def kept = Module.new.tap { |mod| mod.module_eval(written.first.to_s) }::Kept

      it "is guarded in place, every mutant live, on its lines", :aggregate_failures do
        expect(written.first.to_h.fetch(:mutant_ids)).to(eq(written.last.to_a.flat_map(&:ids).sort))
        guarded = /\A  rescue \*\(::Kimera::RUNTIME\.active\?\(\d+\) \? \[\] : \[TypeError\]\)\n\z/
        expect(written.first.to_s.lines.values_at(3, 6)).to(match([guarded, "end\n"]))
      end

      it "answers as written, and raises once its clause is dropped", :aggregate_failures do
        expect(kept.new.gated(->(_) { raise(TypeError) })).to(eq([0, 5]))
        expect { flip(written.last, "drop `rescue TypeError`") { kept.new.gated(->(_) { raise(TypeError) }) } }
          .to(raise_error(TypeError))
      end
    end

    it "leaves a file with no point to guard as written" do
      program = "module Kept\n  Point = Data.define(:x) do\n    def big? = x.positive?\n  end\nend\n"
      result, = woven(program, %w[comparison])
      expect([result.to_s, result.to_h.fetch(:mutant_ids)]).to(eq([program, []]))
    end

    # A registry scanned before the file changed: its first point now lies in
    # a comment, outside every statement, and is dropped alone.
    it "drops a point the file no longer holds where it was scanned, and keeps the rest", :aggregate_failures do
      registry = scan("def a(x) = x > 1\ndef b(y) = y > 2\n", %w[comparison])
      result = nil
      expect { result = described_class.new(registry).synthesize("x.rb", "#ef a(x) = x > 1\ndef b(y) = y > 2\n") }
        .to(output(/x\.rb: 1 mutation point\(s\) at line 1 are unguardable/).to_stderr)
      expect(result.to_h.values_at(:mutant_ids, :skipped_unsafe))
        .to(eq([registry.to_a.last.ids, registry.to_a.first.ids]))
    end

    it "guards a `begin`'s clause outside every definition where it stands", :aggregate_failures do
      program = "CHECK = ->(x) do\n  begin\n    x.call\n  rescue ArgumentError\n    x > 1\n  end\nend\nX = __LINE__\n"
      result, registry = woven(program, %w[rescue_clause comparison])
      expect([result.to_h.fetch(:mutant_ids).size, changed(result.to_s, program)]).to(eq([registry.each.count, [4, 5]]))
      expect(result.to_s.lines[3]).to(eq("  rescue *(::Kimera::RUNTIME.active?(1) ? [] : [ArgumentError])\n"))
    end

    # R6B5-M2: written whole, a class sat on its first line and `__LINE__` in
    # it read 1; the statement is written whole only where that keeps every
    # line.
    def held
      "class Held; CHECK = ->(x) { begin; x.call; rescue ArgumentError; 0; end }; end\nclass Laid\n  CHECK = " \
        "->(x) do\n    begin\n      x.call\n    rescue ArgumentError\n      __LINE__\n    end\n  end\nend\n"
    end

    it "writes the statement of the file that holds such a point whole, on its own line only", :aggregate_failures do
      whole!
      result = nil
      expect { result, = woven(held, %w[rescue_clause]) }
        .to(output(/1 mutation point\(s\) at line 4 are unguardable/).to_stderr)
      expect([changed(result.to_s, held), result.to_h.fetch(:mutant_ids)]).to(eq([[1], [1]]))
      expect(result.to_s).to(start_with("class Held; CHECK = ->(x) {; if ::Kimera::RUNTIME.active?(1); x.call;"))
    end

    it "writes a definition whole, on its lines, when an alternative must break a line", :aggregate_failures do
      program = "def m(s)\n  s.match?(/a\n   b/x) && s.size > 1\nend\n"
      result = nil
      expect { result, = woven(program, %w[boolean_connective]) }.not_to(output.to_stderr)
      expect(
        [
          result.to_s.lines.size,
          result.to_s
        ]
      ).to(match([4, start_with("def m(s); if ::Kimera::RUNTIME.active?(1); ")]))
    end

    it "leaves a point unguarded whose definition can't be written on its lines", :aggregate_failures do
      program = "def m(s) = s.match?(/a\n   b/x) && s.size > 1\ndef n(a) = a > 1\n"
      result = nil
      expect { result, = woven(program, %w[boolean_connective comparison]) }
        .to(output(/1 mutation point\(s\) at line 1 are unguardable/).to_stderr)
      expect([changed(result.to_s, program), result.to_h.fetch(:mutant_ids).size]).to(eq([[2, 3], 4]))
    end

    it "guards a call across a heredoc's lines in place, its alternatives on one line", :aggregate_failures do
      program = "def m(a)\n  a.push([1,\n    2], <<~TEXT)\n    body\n  TEXT\nend\n"
      result, registry = woven(program, %w[argument_drop])
      expect([changed(result.to_s, program), loaded(result.to_s).m([])]).to(eq([[2, 3], [[1, 2], "body\n"]]))
      expect(flip(registry, registry.each.first.first.to_s) { loaded(result.to_s).m([]) }).to(eq(["body\n"]))
    end

    it "writes an alternative whose kept text breaks a line afresh, on one line" do
      program = "def open?(a, b, c)\n  a.positive? &&\n    b.positive? && c.positive?\nend\n\ndef here = __LINE__\n"
      result, = woven(program, %w[boolean_connective])
      expect([result.to_s.lines.size, loaded(result.to_s).here]).to(eq([6, 6]))
    end
  end
end
