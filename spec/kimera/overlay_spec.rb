# frozen_string_literal: true

require "kimera/registry/builder"
require "kimera/synthesis/overlay"

RSpec.describe(Kimera::Overlay) do
  def synth(source)
    registry = Kimera::RegistryScan.new.source(source, file: "x.rb")
    [Kimera::Overlay.new(registry).synthesize("x.rb", source), registry]
  end

  def materialize(source)
    result, registry = synth(source)
    mod = Module.new
    mod.module_eval(result.source)
    [mod, registry]
  end

  def subject(result)
    mod = Module.new
    mod.module_eval(result.source)
    Object.new.extend(mod)
  end

  # The whole-file weave and its fallbacks: what kimera writes for a file
  # whose guards it can't splice into the source.
  def unspliced
    allow(Kimera::Overlay::Stitch).to(receive(:new).and_return(instance_double(Kimera::Overlay::Stitch, result: nil)))
  end

  # What the block answers with the mutant of that label on.
  def flipped(registry, label, &) = Kimera::RUNTIME.during(registry.each.find { |m, _p| m.label == label }.first.id, &)

  describe "round-tripping gnarly expressions" do
    corpus = [
      "a > b",
      "a > b && c < d",
      "a > b || c <= d && e == f",
      "(a > b) ? 1 : 2",
      "return true if a >= b",
      "x = a > b && (c || d)",
      "foo(a > b, c < d)",
      "arr.select { |x| x > 0 && x < 10 }",
      "a > b ? (c == d) : (e != f)",
      "!(a > b) && c",
      "foo(a || b || c)",
      "@memo ||= foo(a && b && c)"
    ].freeze

    corpus.each do |snippet|
      it "produces valid, reparseable Ruby for: #{snippet}", :aggregate_failures do
        source = "def m(a = 1, b = 2, c = 3, d = 4, e = 5, f = 6, arr = [1, 2])\n  #{snippet}\nend\n"
        result, = synth(source)
        # Check MRI too: whitequark and prism disagree on some malformed output.
        expect { Kimera::Scribe.parse(result.source) }.not_to(raise_error)
        expect { RubyVM::InstructionSequence.compile(result.source) }.not_to(raise_error)
      end
    end
  end

  describe "guards in keyword-argument positions" do
    # A guard written as a keyword `if` right after `return` reads as a
    # modifier, so it is written as a ternary there. The extended operators plant guards in the returned chain.
    let(:extended_keys) do
      (Kimera::Operators::DEFAULT_KEYS + %w[string_literal return_value argument_drop element_drop]).freeze
    end

    let(:guarded_return) do
      <<~RUBY
        def permission_mode(mode)
          return mode.tr("-", "_").to_sym if mode

          :ask
        end
      RUBY
    end

    def extended(source)
      registry = Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: extended_keys)).source(
        source, file: "x.rb"
      )
      [Kimera::Overlay.new(registry).synthesize("x.rb", source), registry]
    end

    it "emits MRI-valid Ruby for a guarded receiver chain under return" do
      result, = extended(guarded_return)

      expect { RubyVM::InstructionSequence.compile(result.source) }.not_to(raise_error)
    end

    it "keeps baseline behaviour on both paths of the guarded return", :aggregate_failures do
      result, = extended(guarded_return)
      subject = subject(result)

      expect(subject.permission_mode("auto-accept")).to(be(:auto_accept))
      expect(subject.permission_mode(nil)).to(be(:ask))
    end

    it "still selects a mutant inside the returned chain at runtime" do
      result, registry = extended(guarded_return)
      subject = subject(result)

      mutant = registry.each.find { |m, _p| m.label == "return => return nil" }.first
      Kimera::RUNTIME.during(mutant.id) { expect(subject.permission_mode("auto-accept")).to(be_nil) }
    end
  end

  describe "behavioural equivalence at baseline (active = nil)" do
    def baseline
      Class.new { def greater?(lhs, rhs) = lhs > rhs && rhs < 10 }.new
    end

    it "matches the original for every corpus expression" do
      original = baseline
      subject = Object.new.extend(materialize("def m(a, b)\n  a > b && b < 10\nend\n").first)
      cases = [[5, 3], [1, 9], [20, 20], [11, 11]]
      cases.each { |a, b| expect(subject.m(a, b)).to(eq(original.greater?(a, b)), "mismatch at (#{a},#{b})") }
    end
  end

  describe "activating a mutant changes behaviour" do
    def comparison
      mod, registry = materialize("def gt(a, b)\n  a > b\nend\n")
      [Object.new.extend(mod), registry.each.find { |m, _p| m.label == "> => <" }.first]
    end

    it "flips a comparison when its mutant is active", :aggregate_failures do
      subject, mutant = comparison
      expect(subject.gt(2, 1)).to(be(true))
      Kimera::RUNTIME.during(mutant.id) { expect(subject.gt(2, 1)).to(be(false)) }
    end
  end

  describe "magic comments" do
    # A written tree has no comments, magic ones included. Without them string
    # literals turn mutable.
    it "preserves # frozen_string_literal: true across synthesis" do
      source = "# frozen_string_literal: true\ndef m(a = 1, b = 2)\n  a > b\nend\n"
      result, = synth(source)
      expect(result.source).to(start_with("# frozen_string_literal: true\n"))
    end

    it "preserves a shebang followed by a magic comment" do
      source = "#!/usr/bin/env ruby\n# frozen_string_literal: true\ndef m(a = 1, b = 2)\n  a > b\nend\n"
      result, = synth(source)
      expect(result.source.lines.first(2))
        .to(eq(["#!/usr/bin/env ruby\n", "# frozen_string_literal: true\n"]))
    end

    it "keeps frozen-literal behaviour in the overlaid method" do
      mod, = materialize("# frozen_string_literal: true\ndef greeting\n  \"hi\"\nend\n")
      subject = Object.new.extend(mod)
      expect(subject.greeting).to(be_frozen)
    end

    it "does not prefix source that has no magic comments" do
      result, = synth("def m(a, b)\n  a > b\nend\n")
      expect(result.source).to(start_with("def m"))
    end
  end

  describe "match-pattern position" do
    # A literal in a case/in pattern is syntax. Guarding it yields invalid Ruby.
    it "does not mutate a boolean literal inside a case/in pattern", :aggregate_failures do
      source = "def kind(x, a, b)\n  case x\n  in true then a > b\n  else a < b\n  end\nend\n"
      result, registry = synth(source)
      expect(registry.points.map(&:original_source)).not_to(include("true"))
      expect { Kimera::Scribe.parse(result.source) }.not_to(raise_error)
    end

    it "still mutates the guarded branch bodies of a case/in" do
      source = "def kind(x, a, b)\n  case x\n  in Integer then a > b\n  end\nend\n"
      _result, registry = synth(source)
      expect(registry.points.map(&:original_source)).to(include("a > b"))
    end
  end

  describe "interpolated-literal parts" do
    # A guard is an if node, which unparser wouldn't emit as a direct dstr child.
    # It must be re-wrapped as a #{} interpolation.
    def synthesis(source, keys)
      registry = Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: keys)).source(source, file: "x.rb")
      [Kimera::Overlay.new(registry).synthesize("x.rb", source), registry]
    end

    def banner
      synthesis("def banner(v)\n  \"kimera \#{v}\"\nend\n", %w[string_literal])
    end

    def segment
      result, registry = banner
      [subject(result), registry.points.find { |p| p.original_source == "kimera " }]
    end

    it "guards a plain segment of an interpolated string as valid Ruby", :aggregate_failures do
      result, registry = banner
      part = registry.points.find { |p| p.original_source == "kimera " }
      expect(result.mutant_ids).to(include(*part.ids))
      expect { Kimera::Scribe.parse(result.source) }.not_to(raise_error)
    end

    it "flips the segment live when its mutant is active", :aggregate_failures do
      subject, part = segment
      expect(subject.banner("1.0")).to(eq("kimera 1.0"))
      Kimera::RUNTIME.during(part.mutants.first.id) { expect(subject.banner("1.0")).to(eq("1.0")) }
    end

    # `"a " "b"` nests a dstr in a dstr, which unparser refused once guarded.
    # The inner parts get spliced into the parent.
    def splice
      result, registry = synthesis(
        "def m(a, b)\n  \"Found \#{a} mutants \" \\\n    \"across \#{b} files.\"\nend\n", %w[string_literal]
      )
      [result, subject(result), registry.points.find { |p| p.original_source == "across " }]
    end

    it "splices juxtaposed strings so a guarded segment stays emittable", :aggregate_failures do
      result, subject, part = splice
      expect { Kimera::Scribe.parse(result.source) }.not_to(raise_error)
      expect(subject.m(3, 2)).to(eq("Found 3 mutants across 2 files."))
      Kimera::RUNTIME.during(part.mutants.first.id) { expect(subject.m(3, 2)).to(eq("Found 3 mutants 2 files.")) }
    end

    # A guarded whole segment becomes a bare `#{}`, which can't start a
    # juxtaposition, so parts flatten into one dstr. The middle interpolation
    # forces that path. Exact output pins the coalescing predicates.
    def flatten
      result, registry = synthesis("def m(x)\n  \"alpha \" \"beta \#{x} gamma \" \"delta\"\nend\n", %w[string_literal])
      [result, subject(result), registry.points.find { |p| p.original_source == '"alpha "' }]
    end

    it "flattens and coalesces a guarded whole-segment juxtaposition", :aggregate_failures do
      result, subject, alpha = flatten
      expect { Kimera::Scribe.parse(result.source) }.not_to(raise_error)
      expect(subject.m(1)).to(eq("alpha beta 1 gamma delta"))
      Kimera::RUNTIME.during(alpha.mutants.first.id) { expect(subject.m(1)).to(eq("beta 1 gamma delta")) }
    end

    it "round-trips guarded parts of dsym, regexp and xstr literals" do
      source = <<~RUBY
        def combo(v)
          [:"pre \#{v}", /pre \#{v}/]
        end
      RUBY
      result, = synthesis(source, %w[string_literal])
      expect { Kimera::Scribe.parse(result.source) }.not_to(raise_error)
    end

    # Merging a multi-line %r{}x's str parts could leave no delimiter unparser
    # could emit, which sinks the whole file (mastodon lost 107 mutants to it).
    def expression
      source = <<~'RUBY'
        PATTERN = %r{
          a/b   # a comment
          #{c}
        }x

        def m(a, b)
          a > b
        end
      RUBY
      [Kimera::RegistryScan.new.source(source, file: "re.rb"), source]
    end
    it "leaves the parts of an interpolated regexp unmerged", :aggregate_failures do
      registry, source = expression
      result = nil
      # No warning means no round-trip fallback.
      expect { result = described_class.new(registry).synthesize("re.rb", source) }.not_to(output.to_stderr)
      expect(result.mutant_ids.size).to(eq(registry.count))
      expect { Kimera::Scribe.parse(result.source) }.not_to(raise_error)
    end

    it "keeps a pure string juxtaposition uncoalesced" do
      # Coalescing would leave a lone str child, which unparser refused.
      mod, = materialize("def m(a, b)\n  [\"a \" \"b\", a > b]\nend\n")
      subject = Object.new.extend(mod)
      expect(subject.m(2, 1)).to(eq(["a b", true]))
    end

    it "coalesces plain parts spliced out of a nested juxtaposition", :aggregate_failures do
      # Splicing the inner dstr leaves adjacent str parts, which unparser refused.
      result, = synth("def m(a, b)\n  \"x\" \"y\#{a > b}z\" \"w\"\nend\n")
      expect { RubyVM::InstructionSequence.compile(result.source) }.not_to(raise_error)
      subject = subject(result)
      expect(subject.m(2, 1)).to(eq("xytruezw"))
    end
  end

  describe "non-interpolating containers" do
    # Str coalescing must apply only inside dstr/dsym/regexp/xstr.
    it "leaves adjacent string elements of an array untouched" do
      mod, = materialize("def m(a, b)\n  [\"a\", \"b\", (a > b)]\nend\n")
      subject = Object.new.extend(mod)
      expect(subject.m(2, 1)).to(eq(["a", "b", true]))
    end
  end

  describe "block-attached calls" do
    # Prism's call span includes the block, so directives land on the block
    # node and must reach through to the inner send.
    def synthesis(source, keys)
      registry = Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: keys)).source(source, file: "x.rb")
      [Kimera::Overlay.new(registry).synthesize("x.rb", source), registry]
    end

    def navigation
      result, registry = synthesis("def first_neg(xs)\n  xs&.find { |a| a < 0 }\nend\n", %w[safe_navigation])
      [result, subject(result), registry.each.find { |m, _p| m.label == "&. => ." }.first]
    end

    # Returns [result, whether nil raised].
    def activated(subject, mutant)
      Kimera::RUNTIME.during(mutant.id) do
        [
          subject.first_neg([1, -2]),
          begin
            subject.first_neg(nil)
            false
          rescue NoMethodError
            true
          end
        ]
      end
    end

    it "strips safe navigation on a call with a block", :aggregate_failures do
      result, subject, mutant = navigation
      expect { Kimera::Scribe.parse(result.source) }.not_to(raise_error)
      expect([subject.first_neg([1, -2]), subject.first_neg(nil)]).to(eq([-2, nil]))
      expect(activated(subject, mutant)).to(eq([-2, true]))
    end

    it "drops an argument of a call with a block" do
      source = "def m(xs)\n  xs.each_slice(2) { |s| yield s }\nend\n"
      result, = synthesis(source, %w[argument_drop])
      expect { Kimera::Scribe.parse(result.source) }.not_to(raise_error)
    end
  end

  describe "reopening Struct/Data value objects in place" do
    # described_class is bound before the overlay runs. Rebinding the constant
    # would leave that reference uninstrumented, so its mutants would survive.
    def overlay(source, const, keys: nil)
      registry = Kimera::RegistryScan.new(operators: operators(keys)).source(source, file: "x.rb")
      result = Kimera::Overlay.new(registry).synthesize("x.rb", source)
      verbose = $VERBOSE
      $VERBOSE = nil
      TOPLEVEL_BINDING.eval(source) # app load: binds const
      held = TOPLEVEL_BINDING.eval(const) # what described_class holds
      TOPLEVEL_BINDING.eval(result.source, "x.rb")
      [held, registry, result]
    ensure
      $VERBOSE = verbose
    end

    def operators(keys)
      keys ? Kimera::Operators.build(keys: keys) : Kimera::Operators.build
    end

    def live(const)
      TOPLEVEL_BINDING.eval(const)
    end

    let(:struct_source) do
      <<~RUBY
        module KimeraReopenProbe
          Point = Struct.new(:x, :y, keyword_init: true) do
            def bigger?
              x > y
            end
          end
        end
      RUBY
    end

    let(:tag_source) do
      <<~RUBY
        module KimeraReopenProbe
          Tag = Struct.new(:name, keyword_init: true) do
            def to_h
              { "name" => name }
            end
          end
        end
      RUBY
    end

    let(:span_source) do
      <<~RUBY
        module KimeraReopenProbe
          Span = Data.define(:lo, :hi) do
            def width
              hi - lo
            end
          end
        end
      RUBY
    end

    it "emits a reopen (class_eval on the existing class), not a bare rebind", :aggregate_failures do
      result, = synth(struct_source)
      expect(result.source).to(include("class_eval"))
      expect(result.source).to(include("const_defined?(:Point, false)"))
    end

    it "preserves the constant's object identity across the overlay" do
      held, = overlay(struct_source, "KimeraReopenProbe::Point")
      expect(live("KimeraReopenProbe::Point")).to(equal(held))
    end

    it "fires guards through a reference captured before the overlay", :aggregate_failures do
      held, registry = overlay(struct_source, "KimeraReopenProbe::Point")
      expect(held.new(x: 2, y: 1).bigger?).to(be(true))
      expect(flipped(registry, "> => <") { held.new(x: 2, y: 1).bigger? }).to(be(false))
    end

    it "instruments to_h key literals reachable through described_class", :aggregate_failures do
      held, registry = overlay(tag_source, "KimeraReopenProbe::Tag", keys: %w[string_literal])
      expect(held.new(name: "a").to_h).to(eq("name" => "a"))
      Kimera::RUNTIME.during(registry.points.find { |p| p.original_source == '"name"' }.mutants.first.id) do
        expect(held.new(name: "a").to_h).to(eq("" => "a"))
      end
    end

    it "leaves factory lookalikes that are not casgn+block+factory untouched", :aggregate_failures do
      # One lookalike per detection guard: non-block value (Alpha), csend (Beta),
      # a block taking parameters (Gamma), dynamic receiver (Delta), receiverless (Epsilon),
      # non-casgn (take).
      source = <<~RUBY
        Alpha = [Struct.new(:x)]
        Beta = Struct&.new(:x) do
          def cmp(a, b); a > b; end
        end
        Gamma = Foo.new(:x) do |c|
          def cmp(a, b); a > b; end
        end
        Delta = Struct().new(:x) do
          def cmp(a, b); a > b; end
        end
        Epsilon = build do
          def cmp(a, b); a > b; end
        end
        take(Struct.new(:x) { nil })
      RUBY
      result, = synth(source)
      expect(result.mutant_ids).not_to(be_empty)
      expect(result.source).not_to(include("class_eval"))
      expect { Kimera::Scribe.parse(result.source) }.not_to(raise_error)
    end

    it "reopens a Data.define value object in place too", :aggregate_failures do
      held, registry = overlay(span_source, "KimeraReopenProbe::Span", keys: %w[arithmetic])
      expect(held.new(lo: 1, hi: 5).width).to(eq(4))
      expect(flipped(registry, "- => +") { held.new(lo: 1, hi: 5).width }).to(eq(6))
    end
  end

  describe "memoization routing" do
    let(:total_source) do
      <<~RUBY
        def total
          @total ||= compute(a > b)
        end
      RUBY
    end

    let(:mixed_source) do
      <<~RUBY
        def a
          @cached ||= heavy(x > y)
        end

        def b(p, q)
          p < q
        end
      RUBY
    end

    it "excludes mutants inside a ||= memoization from the schema path", :aggregate_failures do
      result, registry = synth(total_source)
      point = registry.points.find { |p| p.original_source == "a > b" }
      expect(point).to(have_attributes(safe?: false, unsafe_reason: a_string_matching(/memoized/)))
      expect(result.source).not_to(include("active?"))
      expect(result.skipped_unsafe).to(include(*point.ids))
    end

    it "returns the source verbatim when no point is schema-safe", :aggregate_failures do
      # A round-trip would drop comments and formatting.
      source = "# load-order comment\ndef total\n  @total ||= compute(a > b)\nend\n"
      result, = synth(source)
      expect(result.source).to(eq(source))
      expect(result.skipped_unsafe).not_to(be_empty)
    end

    it "still mutates non-memoized points in the same file", :aggregate_failures do
      result, registry = synth(mixed_source)
      memoized, live = ["x > y", "p < q"].map { |s| registry.points.find { |p| p.original_source == s } }
      expect([memoized.safe?, live.safe?]).to(eq([false, true]))
      expect(result.mutant_ids).to(include(*live.ids))
      expect(result.mutant_ids).not_to(include(*memoized.ids))
    end
  end

  # Only one mutant is active at a time, so under a point's guard every guard
  # beneath it is false: its variants copy the bare subtree, not the guarded
  # one. Copying the guards made size multiply along a nesting path.
  describe "nested points" do
    let(:source) { "def m(a)\n  ((a + 1) * 2 - 3).abs.succ.to_s\nend\n" }
    let(:registry) do
      Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: ["all"])).source(source, file: "x.rb")
    end
    let(:overlay) { described_class.new(registry) }
    let(:result) { overlay.synthesize("x.rb", source) }

    # A spliced guard names each mutant in its test and, but for the last,
    # once more in its chain of alternatives.
    it "emits each mutant's guard once, however deep its point sits", :aggregate_failures do
      guards = result.source.scan(/active\?\((\d+)\)/).flatten.map { |id| Integer(id) }
      expect(result.mutant_ids.size).to(be > 10)
      expect([guards.uniq, guards.tally.values.max]).to(match([match_array(result.mutant_ids), 2]))
    end

    def loaded(text) = Object.new.extend(Module.new.tap { |mod| mod.module_eval(text) })

    def outcomes(receiver)
      [-4, 0, 3].map do |a|
        receiver.m(a)
      rescue StandardError => error
        error.class
      end
    end

    def flip(live, id)
      Kimera::RUNTIME.during(id) { outcomes(live) }
    end

    # chain_link_deletion reaches into its receiver, a node with points of its own.
    # Bakes come first: kimera's own guards read the same runtime when it mutates itself.
    it "behaves like each mutant's bake when that mutant is active" do
      live = loaded(result.source)
      baked = result.mutant_ids.to_h { |id| [id, outcomes(loaded(overlay.bake("x.rb", source, id)))] }
      flipped = baked.keys.to_h { |id| [id, flip(live, id)] }
      expect(flipped).to(eq(baked))
    end
  end

  # Prism sees a literal -1 inside `--1`. The parser gem folded both minuses
  # into one literal, so that point had no node to guard; kimera now guards
  # the tree it scans, so the point is live like any other.
  describe "a literal inside `--1`" do
    let(:source) { "def m(a)\n  a > 0 && --1\nend\n" }
    let(:registry) do
      Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: %w[numeric_literal comparison]))
        .source(source, file: "x.rb")
    end

    it "is guarded, not reported unmutatable", :aggregate_failures do
      result = described_class.new(registry).synthesize("x.rb", source)
      inner = registry.points.find { |point| point.original_source == "-1" }
      expect(result.skipped_unsafe).to(be_empty)
      expect(result.mutant_ids).to(match_array(registry.points.flat_map(&:ids)))
      expect(inner).to(be_safe)
    end
  end

  # From Lobsters: Ruby reads "\xFF" in a UTF-8 file as that byte, but the
  # parser gem rejected the literal, so its whole file was unmutatable.
  describe "a string escape that is invalid UTF-8" do
    def escaped(source, keys = %w[string_literal arithmetic])
      operators = Kimera::Operators.build(keys: keys)
      registry = Kimera::RegistryScan.new(operators: operators).source(source, file: "escaped.rb")
      [described_class.new(registry).synthesize("escaped.rb", source), registry]
    end

    let(:source) do
      <<~'RUBY'
        def content_type(data)
          data.start_with?("\xFF\xD8\xFF".b) ? "image/jpeg" : "image/png"
        end

        def scaled(size) = size * 2
      RUBY
    end

    # unparser could not write such a byte back into a plain heredoc, so the
    # file was spliced per method and the heredoc's method left unmutated.
    let(:heredoc) do
      "def banner(size)\n  return if size < 2 * 2\n  <<~TEXT\n    \\xFF\n    end\n  TEXT\nend\n\n#{source}"
    end

    it "mutates the whole file, the literal's own point too" do
      result, registry = escaped(source)
      expect([result.mutant_ids.size, result.skipped_unsafe]).to(eq([registry.count, []]))
    end

    it "keeps the literal's mutant live", :aggregate_failures do
      result, registry = escaped(source)
      typed = subject(result)
      expect(typed.content_type("\xFF\xD8\xFF\xE0".b)).to(eq("image/jpeg"))
      expect(flipped(registry, '"\xFF\xD8\xFF" => ""') { typed.content_type("\x89PNG".b) }).to(eq("image/jpeg"))
    end

    it "mutates a file whose heredoc holds the byte, the heredoc's method too", :aggregate_failures do
      result, registry = nil
      expect { result, registry = escaped(heredoc, %w[arithmetic comparison]) }.not_to(output.to_stderr)
      expect([result.mutant_ids.size, result.skipped_unsafe]).to(eq([registry.count, []]))
    end

    it "writes the heredoc's byte through" do
      result, = escaped(heredoc, %w[arithmetic comparison])
      expect(subject(result).banner(5).bytes).to(eq([0xFF, 10, 101, 110, 100, 10]))
    end
  end

  describe "write fallback" do
    # `alias` takes a bare name, so the tree weave's guard where one stood
    # does not parse. Only those points should drop, not the file.
    before { unspliced }

    let(:source) { "class MatchRepro\n  def extract(limit)\n    alias c d\n    limit > 1\n  end\nend\n" }
    let(:unguardable) do
      /match_repro\.rb: 2 mutation point\(s\) at line 3 are unguardable \(kimera could not write them\)/
    end

    def scan
      Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: %w[symbol_literal comparison]))
        .source(source, file: "match_repro.rb")
    end

    # Count, line and reason are all triage signal, so pin the exact message.
    def fallback
      registry = scan
      result = nil
      expect { result = described_class.new(registry).synthesize("match_repro.rb", source) }
        .to(output(unguardable).to_stderr)
      [registry, result]
    end

    it "drops only the unguardable points and keeps the rest live", :aggregate_failures do
      registry, result = fallback
      expect([result.mutant_ids, result.skipped_unsafe])
        .to(satisfy { |(m, s)| !m.empty? && !s.empty? && !m.intersect?(s) })
      expect(result.mutant_ids.size + result.skipped_unsafe.size).to(eq(registry.count))
      expect { Kimera::Scribe.parse(result.source) }.not_to(raise_error)
    end

    it "reports the dropped points as unmutatable, with the reason", :aggregate_failures do
      registry, result = fallback
      dropped = registry.points.reject(&:safe?)
      expect(dropped.flat_map(&:ids)).to(eq(result.skipped_unsafe))
      expect(dropped.map(&:unsafe_reason).uniq).to(eq(["unmutatable: kimera could not write its guard"]))
    end

    # Every weave fails to render.
    def unweavable
      build = Kimera::Overlay::FileWeave.method(:new)
      allow(Kimera::Overlay::FileWeave).to(receive(:new)) do |*arguments, **options|
        build.call(*arguments, **options).tap { |weave| allow(weave).to(receive(:attempt).and_return(nil)) }
      end
    end

    it "raises when no point is guardable and the whole file would not parse" do
      unweavable
      expect { described_class.new(scan).synthesize("match_repro.rb", source) }
        .to(raise_error(Kimera::Scribe::Unreadable, Kimera::Overlay::FileWeave::UNGUARDABLE))
    end

    # A failure outside any method can't be fixed by dropping points. Splicing
    # per method keeps the rest of the file verbatim.
    describe "per-method splicing" do
      let(:splice_source) do
        <<~RUBY
          class Spliced
            ODDITY = :unemittable

            def compare(a, b)
              a > b
            end

            def also(a, b)
              a < b
            end
          end
        RUBY
      end

      # Nested points belong to the outer method. Claiming them twice would
      # splice overlapping edits.
      let(:nested_source) do
        <<~RUBY
          class Nested
            def outer
              Class.new do
                def inner(a, b)
                  a > b
                end
              end
            end

            def  untouched_by_points
              :ok
            end
          end
        RUBY
      end
      # Re-evaluating `Name = Data.define do` would build a second class that
      # no existing instance belongs to, so no spliced guard would ever run.
      let(:value_source) do
        <<~RUBY
          module Spliced
            Point = Data.define(:x) do
              def big? = x > 10
            end
            ::SplicedTop = Struct.new(:x) { def small? = x < 10 }
            Spliced::Nested = Data.define(:x) do
              def same? = x == 10
            end
            Plain = Data.define(:x)
            Other = Class.new { def odd?(x) = x > 1 }
            Callback = proc { :noop }
            Safe = Data&.define(:x) do
              def ok? = x > 1
            end
            helper = Struct.new(:y) { def tiny? = y < 1 }
          end
        RUBY
      end

      # Whole-file emission fails; individual methods are fine.
      def unwritable!
        allow(Kimera::Scribe).to(receive(:new).and_wrap_original) do |original, node|
          unless node.type == :def_node
            raise(RuntimeError, "Could not find a round tripping solution for regexp")
          end
          original.call(node)
        end
      end

      def spliced
        registry = Kimera::RegistryScan.new.source(splice_source, file: "spliced.rb")
        unwritable!
        result = nil
        expect { result = described_class.new(registry).synthesize("spliced.rb", splice_source) }
          .to(output(/spliced\.rb: could not write the whole file; 4 mutant\(s\) spliced per method/).to_stderr)
        [registry, result]
      end

      it "keeps every method's mutants and the untouched source verbatim", :aggregate_failures do
        registry, result = spliced
        expect(result.mutant_ids.size).to(eq(registry.count))
        expect(result.source).to(include("ODDITY = :unemittable"))
        expect(result.source).to(include("::Kimera::RUNTIME.active?"))
        expect(Prism.parse(result.source)).to(be_success)
      end

      # Kimera writes no tree but a method, and not the method named compare.
      def unparsing_methods
        allow(Kimera::Scribe).to(receive(:new).and_wrap_original) do |original, node|
          raise(RuntimeError, "boom") unless node.type == :def_node
          raise(RuntimeError, "boom") if node.name == :compare
          original.call(node)
        end
      end

      def partial
        registry = Kimera::RegistryScan.new.source(splice_source, file: "spliced.rb")
        unparsing_methods
        result = nil
        expect { result = described_class.new(registry).synthesize("spliced.rb", splice_source) }
          .to(output(/2 mutant\(s\) spliced per method, 2 reported unmutatable/).to_stderr)
        [registry, result]
      end

      it "accounts for every point exactly once", :aggregate_failures do
        registry, result = partial
        expect(result.mutant_ids.size + result.skipped_unsafe.size).to(eq(registry.count))
        expect(result.mutant_ids & result.skipped_unsafe).to(be_empty)
      end

      it "reports the points of a method it could not re-emit as unmutatable", :aggregate_failures do
        registry, = partial
        dropped, kept = registry.points.partition { |point| point.method_name.to_s == "compare" }
        expect(dropped.map(&:unsafe_reason).uniq).to(eq(["unmutatable: kimera could not write its method"]))
        expect(kept).to(all(be_safe))
      end

      # A rebuild failure outside any method is a Kimera bug. Splicing would hide it.
      def broken
        build = Kimera::Guardrail.method(:new)
        allow(Kimera::Guardrail).to(receive(:new)) do |*arguments|
          build.call(*arguments).tap do |guardrail|
            allow(guardrail).to(receive(:reopen).and_wrap_original) do |original, node|
              raise(NoMethodError, "undefined method 'children' for nil") if node.type == :constant_write_node
              original.call(node)
            end
          end
        end
      end

      it "refuses to splice when the rebuild fails, rather than the emission" do
        registry = Kimera::RegistryScan.new.source(splice_source, file: "spliced.rb")
        synth = described_class.new(registry)
        broken
        expect { synth.synthesize("spliced.rb", splice_source) }
          .to(raise_error(Kimera::Scribe::Unreadable, Kimera::Overlay::FileWeave::UNGUARDABLE))
      end

      def invalid!
        allow(Kimera::Scribe).to(receive(:new).and_wrap_original) do |_original, node|
          unless node.type == :def_node
            raise(RuntimeError, "Could not find a round tripping solution for regexp")
          end
          "def broken(" # syntactically impossible splice
        end
      end

      it "refuses to splice a result that would not parse" do
        registry = Kimera::RegistryScan.new.source(splice_source, file: "spliced.rb")
        invalid!
        expect { described_class.new(registry).synthesize("spliced.rb", splice_source) }
          .to(raise_error(Kimera::Scribe::Unreadable, Kimera::Overlay::FileWeave::UNGUARDABLE))
      end

      def nested
        registry = Kimera::RegistryScan.new.source(nested_source, file: "nested.rb")
        unwritable!
        [registry, described_class.new(registry).synthesize("nested.rb", nested_source)]
      end

      it "claims a nested definition's points once, for the outer method", :aggregate_failures do
        registry, result = nested
        expect(result.mutant_ids.size).to(eq(registry.count))
        expect(Prism.parse(result.source)).to(be_success)
        # Methods without points aren't re-emitted, so kimera can't normalise this.
        expect(result.source).to(include("def  untouched_by_points"))
      end

      def compiled
        registry = Kimera::RegistryScan.new.source(splice_source, file: "spliced.rb")
        unwritable!
        mod = Module.new
        mod.module_eval(described_class.new(registry).synthesize("spliced.rb", splice_source).source)
        [mod.const_get(:Spliced), registry.each.find { |m, _p| m.label == "> => <" }.first]
      end

      it "still selects a spliced mutant at runtime", :aggregate_failures do
        klass, flip = compiled
        expect(klass.new.compare(2, 1)).to(be(true))
        Kimera::RUNTIME.during(flip.id) { expect(klass.new.compare(2, 1)).to(be(false)) }
      end

      def reopened
        registry = Kimera::RegistryScan.new.source(value_source, file: "value.rb")
        unwritable!
        source = nil
        announced = /value\.rb: could not write the whole file; #{registry.count} mutant\(s\) spliced per method/
        expect { source = described_class.new(registry).synthesize("value.rb", value_source).source }
          .to(output(announced).to_stderr)
        [registry, source]
      end

      # A Point, a SplicedTop and a Nested made before the spliced overlay runs.
      def made_before(source)
        stub_const("Spliced", Module.new)
        stub_const("SplicedTop", nil)
        Kimera::Warnings::SILENCED.during { TOPLEVEL_BINDING.eval(value_source) }
        [Spliced::Point.new(x: 11), SplicedTop.new(20), Spliced::Nested.new(x: 10)].tap do
          Kimera::Warnings::SILENCED.during { TOPLEVEL_BINDING.eval(source) }
        end
      end

      # Each ask's answer with the mutant of its label, at its line, active.
      def flipped(registry, asks)
        asks.map do |label, line, ask|
          at = ->(mutant, point) { mutant.label == label && point.location.start_line == line }
          Kimera::RUNTIME.during(registry.each.find { |mutant, point| at.call(mutant, point) }.first.id) { ask.call }
        end
      end

      it "reopens value-object constants instead of redefining them" do
        _registry, source = reopened
        made = made_before(source)
        expect([Spliced::Point, SplicedTop, Spliced::Nested]).to(eq(made.map(&:class)))
      end

      it "keeps the mutants of the reopened constants' methods live" do
        registry, source = reopened
        point, top, nested = made_before(source)
        asks = [
          ["> => <", 3, -> { point.big? }], ["< => >", 5, -> { top.small? }], ["== => !=", 7, -> { nested.same? }]
        ]
        expect(flipped(registry, asks)).to(eq([false, true, false]))
      end

      # How the splice reopens each kind of constant.
      def reopenings
        lexical = "(is_a?(::Module) ? self : ::Object)"
        [
          "Point = (#{lexical}.const_defined?(:Point, false) ? #{lexical}.const_get(:Point) : " \
            "Data.define(:x)); Point.class_eval do",
          "::SplicedTop = (::Object.const_defined?(:SplicedTop, false) ? ::Object.const_get(:SplicedTop) : " \
            "Struct.new(:x)); ::SplicedTop.class_eval {",
          "Spliced::Nested = (Spliced.const_defined?(:Nested, false) ? Spliced.const_get(:Nested) : " \
            "Data.define(:x)); Spliced::Nested.class_eval do",
          "Other = (#{lexical}.const_defined?(:Other, false) ? #{lexical}.const_get(:Other) : " \
            "Class.new); Other.class_eval {"
        ]
      end

      it "reopens with the constant's own scope, or the lexical one" do
        _registry, source = reopened
        expect(source).to(include(*reopenings))
      end

      it "leaves every other assignment as written", :aggregate_failures do
        _registry, source = reopened
        expect(source).to(include("Plain = Data.define(:x)\n", "Callback = proc { :noop }"))
        expect(source).to(include("Safe = Data&.define(:x) do", "helper = Struct.new(:y) {"))
      end

      it "leaves a file with nothing to splice unreopened" do
        code = "Point = Data.define(:x) do\n  def big? = x > 10\nend\n"
        registry = Kimera::RegistryScan.new.source(code, file: "p.rb")
        allow(Kimera::Scribe).to(receive(:new).and_raise(RuntimeError, "Could not find a round tripping solution"))
        expect { described_class.new(registry).synthesize("p.rb", code) }
          .to(raise_error(Kimera::Scribe::Unreadable, Kimera::Overlay::FileWeave::UNGUARDABLE))
      end
    end

    # giacope/kimera#7: a string interpolating a pattern binding sank every
    # mutant in the file, including ones in unrelated methods.
    describe "a file whose strings interpolate a case/in binding" do
      let(:code) do
        <<~'RUBY'
          class PatternBid
            def big?(value) = value > 10

            def bid(input)
              case input
              in [:parsed, chosen] then ["#{input.first} #{chosen}", chosen]
              end
            end
          end
        RUBY
      end

      # The registry and the overlay, woven without a warning.
      def woven
        registry = Kimera::RegistryScan.new.source(code, file: "bid.rb")
        result = nil
        expect { result = described_class.new(registry).synthesize("bid.rb", code) }.not_to(output.to_stderr)
        [registry, result]
      end

      it "is woven whole, quietly" do
        registry, result = woven
        expect(result.mutant_ids.size).to(eq(registry.count))
      end

      it "still answers as written" do
        _, result = woven
        bid = Module.new.tap { |mod| mod.module_eval(result.source) }.const_get(:PatternBid)
        expect(bid.new.bid([:parsed, 2])).to(eq(["parsed 2", 2]))
      end
    end

    it "does not warn when every point is guardable" do
      code = "def m(a, b)\n  a > b\nend\n"
      registry = Kimera::RegistryScan.new.source(code, file: "clean.rb")
      expect { described_class.new(registry).synthesize("clean.rb", code) }.not_to(output.to_stderr)
    end
  end

  describe "trees kimera writes from the scan" do
    def woven(source, keys)
      registry = Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: keys)).source(source, file: "x.rb")
      [Kimera::Overlay.new(registry).synthesize("x.rb", source), registry]
    end

    let(:alias_probe) { "class AliasProbe\n  def m\n    alias c d\n    1\n  end\nend\n" }

    # `alias` takes a bare name, so a mutant of one is guarded at the alias
    # statement; the tree weave's guard where the name stood would not parse.
    it "guards a bare name at the statement that holds it", :aggregate_failures do
      source = "class AliasProbe\n  def m\n    alias c d\n    1\n  end\nend\n"
      result, registry = woven(source, %w[symbol_literal numeric_literal])
      expect([result.skipped_unsafe, result.mutant_ids]).to(eq([[], registry.points.flat_map(&:ids)]))
      expect(result.source).to(include("? (alias c d) : "))
    end

    it "drops the points whose tree-weave guard Ruby would reject, and keeps the rest", :aggregate_failures do
      unspliced
      result = nil
      expect { result, = woven(alias_probe, %w[symbol_literal numeric_literal]) }
        .to(output(/2 mutation point\(s\) at line 3 are unguardable/).to_stderr)
      expect([result.skipped_unsafe.size, result.source]).to(match([2, include("alias :c :d")]))
      expect(Prism.parse(result.source)).to(be_success)
    end

    # Only `::Kimera::RUNTIME.active?` is a guard; a lookalike is the project's own call.
    it "reports the guards it wrote, not calls that look like them" do
      source = "class Lookalike\n  def m(a)\n    ::Kimera::Flags.active?(9)\n    Foo::Bar.active?(8)\n    " \
        "a > 1\n  end\nend\n"
      result, registry = woven(source, %w[comparison])
      expect(result.mutant_ids).to(eq(registry.points.flat_map(&:ids)))
    end

    def paths
      "module ReopenPath\nend\nReopenPath::Point = Struct.new(:x) do\n  def big?(y) = x > y\nend\n" \
        "::ReopenTop = Struct.new(:x) do\n  def big?(y) = x > y\nend\n"
    end

    it "reopens a value object named by a path with the path's own scope in the source", :aggregate_failures do
      written = woven(paths, %w[comparison]).first.source
      expect(written).to(include("ReopenPath::Point = (ReopenPath.const_defined?(:Point, false) ? ReopenPath"))
      expect(written).to(include("::ReopenTop = (::Object.const_defined?(:ReopenTop, false) ? "))
    end

    it "reopens a value object named by a path with the path's own scope in the tree", :aggregate_failures do
      unspliced
      written = woven(paths, %w[comparison]).first.source
      expect(written).to(include("ReopenPath::Point = if (ReopenPath).const_defined?(:Point, false)\n"))
      expect(written).to(include("  (ReopenPath).const_get(:Point)\n", "ReopenPath::Point.class_eval {"))
      expect(written).to(include("::ReopenTop = if (::Object).const_defined?(:ReopenTop, false)"))
    end

    # A def is a value too: its tail mutant guards the def, so the method that
    # holds it returns nil with the mutant on and defines the method without.
    it "guards a def at a method's tail where it stands" do
      source = "class NestedTail\n  def outer\n    def inner\n    end\n  end\nend\n"
      result, registry = woven(source, %w[return_value])
      held = Module.new.tap { |mod| mod.module_eval(result.source) }::NestedTail.new
      expect([held.outer, Kimera::RUNTIME.during(registry.points.first.ids.first) { held.outer }]).to(eq([:inner, nil]))
    end
  end
end
