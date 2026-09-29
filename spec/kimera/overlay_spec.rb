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

  after { Kimera::Runtime.reset! }

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
      "!(a > b) && c"
    ].freeze

    corpus.each do |expr|
      it "produces valid, reparseable Ruby for: #{expr}", :aggregate_failures do
        source = "def m(a = 1, b = 2, c = 3, d = 4, e = 5, f = 6, arr = [1, 2])\n  #{expr}\nend\n"
        result, = synth(source)
        # Check MRI too: whitequark and prism disagree on some malformed output.
        expect { Unparser.parse(result.source) }.not_to(raise_error)
        expect { RubyVM::InstructionSequence.compile(result.source) }.not_to(raise_error)
      end
    end
  end

  describe "guards in keyword-argument positions" do
    # Unparser may emit a guard as a keyword `if`, which after `return` parses
    # as a modifier. The extended operators plant guards in the returned chain.
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

      Kimera::Runtime.active = nil
      expect(subject.permission_mode("auto-accept")).to(be(:auto_accept))
      expect(subject.permission_mode(nil)).to(be(:ask))
    end

    it "still selects a mutant inside the returned chain at runtime" do
      result, registry = extended(guarded_return)
      subject = subject(result)

      mutant = registry.each.find { |m, _p| m.label == "return => return nil" }.first
      Kimera::Runtime.active = mutant.id
      expect(subject.permission_mode("auto-accept")).to(be_nil)
    end
  end

  describe "behavioural equivalence at baseline (active = nil)" do
    def baseline
      Class.new { def greater?(lhs, rhs) = lhs > rhs && rhs < 10 }.new
    end

    it "matches the original for every corpus expression" do
      Kimera::Runtime.active = nil
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
      Kimera::Runtime.active = nil
      expect(subject.gt(2, 1)).to(be(true))
      Kimera::Runtime.active = mutant.id
      expect(subject.gt(2, 1)).to(be(false))
    end
  end

  describe "magic comments" do
    # Unparser drops magic comments. Without them string literals turn mutable.
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
      expect { Unparser.parse(result.source) }.not_to(raise_error)
    end

    it "still mutates the guarded branch bodies of a case/in" do
      source = "def kind(x, a, b)\n  case x\n  in Integer then a > b\n  end\nend\n"
      _result, registry = synth(source)
      expect(registry.points.map(&:original_source)).to(include("a > b"))
    end
  end

  describe "interpolated-literal parts" do
    # A guard is an if node, which unparser won't emit as a direct dstr child.
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
      expect { Unparser.parse(result.source) }.not_to(raise_error)
    end

    it "flips the segment live when its mutant is active", :aggregate_failures do
      subject, part = segment
      Kimera::Runtime.active = nil
      expect(subject.banner("1.0")).to(eq("kimera 1.0"))
      Kimera::Runtime.active = part.mutants.first.id
      expect(subject.banner("1.0")).to(eq("1.0"))
    end

    # `"a " "b"` nests a dstr in a dstr, which unparser refuses once guarded.
    # The inner parts get spliced into the parent.
    def splice
      result, registry = synthesis(
        "def m(a, b)\n  \"Found \#{a} mutants \" \\\n    \"across \#{b} files.\"\nend\n", %w[string_literal]
      )
      Kimera::Runtime.active = nil
      [result, subject(result), registry.points.find { |p| p.original_source == "across " }]
    end

    it "splices juxtaposed strings so a guarded segment stays emittable", :aggregate_failures do
      result, subject, part = splice
      expect { Unparser.parse(result.source) }.not_to(raise_error)
      expect(subject.m(3, 2)).to(eq("Found 3 mutants across 2 files."))
      Kimera::Runtime.active = part.mutants.first.id
      expect(subject.m(3, 2)).to(eq("Found 3 mutants 2 files."))
    end

    # A guarded whole segment becomes a bare `#{}`, which can't start a
    # juxtaposition, so parts flatten into one dstr. The middle interpolation
    # forces that path. Exact output pins the coalescing predicates.
    def flatten
      result, registry = synthesis("def m(x)\n  \"alpha \" \"beta \#{x} gamma \" \"delta\"\nend\n", %w[string_literal])
      Kimera::Runtime.active = nil
      [result, subject(result), registry.points.find { |p| p.original_source == '"alpha "' }]
    end

    it "flattens and coalesces a guarded whole-segment juxtaposition", :aggregate_failures do
      result, subject, alpha = flatten
      expect { Unparser.parse(result.source) }.not_to(raise_error)
      expect(subject.m(1)).to(eq("alpha beta 1 gamma delta"))
      Kimera::Runtime.active = alpha.mutants.first.id
      expect(subject.m(1)).to(eq("beta 1 gamma delta"))
    end

    it "round-trips guarded parts of dsym, regexp and xstr literals" do
      source = <<~RUBY
        def combo(v)
          [:"pre \#{v}", /pre \#{v}/]
        end
      RUBY
      result, = synthesis(source, %w[string_literal])
      expect { Unparser.parse(result.source) }.not_to(raise_error)
    end

    # Merging a multi-line %r{}x's str parts can leave no delimiter unparser
    # can emit, which sinks the whole file (mastodon lost 107 mutants to it).
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
      expect { Unparser.parse(result.source) }.not_to(raise_error)
    end

    it "keeps a pure string juxtaposition uncoalesced" do
      # Coalescing would leave a lone str child, which unparser refuses.
      mod, = materialize("def m(a, b)\n  [\"a \" \"b\", a > b]\nend\n")
      subject = Object.new.extend(mod)
      Kimera::Runtime.active = nil
      expect(subject.m(2, 1)).to(eq(["a b", true]))
    end

    it "coalesces plain parts spliced out of a nested juxtaposition", :aggregate_failures do
      # Splicing the inner dstr leaves adjacent str parts, which unparser refuses.
      result, = synth("def m(a, b)\n  \"x\" \"y\#{a > b}z\" \"w\"\nend\n")
      expect { RubyVM::InstructionSequence.compile(result.source) }.not_to(raise_error)
      subject = subject(result)
      Kimera::Runtime.active = nil
      expect(subject.m(2, 1)).to(eq("xytruezw"))
    end
  end

  describe "non-interpolating containers" do
    # Str coalescing must apply only inside dstr/dsym/regexp/xstr.
    it "leaves adjacent string elements of an array untouched" do
      mod, = materialize("def m(a, b)\n  [\"a\", \"b\", (a > b)]\nend\n")
      subject = Object.new.extend(mod)
      Kimera::Runtime.active = nil
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
      Kimera::Runtime.active = nil
      [result, subject(result), registry.each.find { |m, _p| m.label == "&. => ." }.first]
    end

    # Returns [result, whether nil raised].
    def activated(subject, mutant)
      Kimera::Runtime.active = mutant.id
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

    it "strips safe navigation on a call with a block", :aggregate_failures do
      result, subject, mutant = navigation
      expect { Unparser.parse(result.source) }.not_to(raise_error)
      expect([subject.first_neg([1, -2]), subject.first_neg(nil)]).to(eq([-2, nil]))
      expect(activated(subject, mutant)).to(eq([-2, true]))
    end

    it "drops an argument of a call with a block" do
      source = "def m(xs)\n  xs.each_slice(2) { |s| yield s }\nend\n"
      result, = synthesis(source, %w[argument_drop])
      expect { Unparser.parse(result.source) }.not_to(raise_error)
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
      Kimera::Runtime.active = nil
      expect(held.new(x: 2, y: 1).bigger?).to(be(true))
      Kimera::Runtime.active = registry.each.find { |m, _p| m.label == "> => <" }.first.id
      expect(held.new(x: 2, y: 1).bigger?).to(be(false))
    end

    it "instruments to_h key literals reachable through described_class", :aggregate_failures do
      held, registry = overlay(tag_source, "KimeraReopenProbe::Tag", keys: %w[string_literal])
      Kimera::Runtime.active = nil
      expect(held.new(name: "a").to_h).to(eq("name" => "a"))
      Kimera::Runtime.active = registry.points.find { |p| p.original_source == '"name"' }.mutants.first.id
      expect(held.new(name: "a").to_h).to(eq("" => "a"))
    end

    it "leaves factory lookalikes that are not casgn+block+factory untouched", :aggregate_failures do
      # One lookalike per detection guard: non-block value (Alpha), csend (Beta),
      # non-factory (Gamma), dynamic receiver (Delta), receiverless (Epsilon),
      # non-casgn (take).
      source = <<~RUBY
        Alpha = [Struct.new(:x)]
        Beta = Struct&.new(:x) do
          def cmp(a, b); a > b; end
        end
        Gamma = Foo.new(:x) do
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
      expect { Unparser.parse(result.source) }.not_to(raise_error)
    end

    it "reopens a Data.define value object in place too", :aggregate_failures do
      held, registry = overlay(span_source, "KimeraReopenProbe::Span", keys: %w[arithmetic])
      Kimera::Runtime.active = nil
      expect(held.new(lo: 1, hi: 5).width).to(eq(4))
      Kimera::Runtime.active = registry.each.find { |m, _p| m.label == "- => +" }.first.id
      expect(held.new(lo: 1, hi: 5).width).to(eq(6))
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

  # Directives that reach into a child must see it without a nested point's
  # dispatch. unwrap must strip only the overlay's own dispatches.
  describe "#unwrap" do
    let(:synth) { Kimera::Guardrail.new(Kimera::SourceMap.new("def m(a, b)\n  a > b\nend\n"), []) }

    def ast(type, *children)
      Parser::AST::Node.new(type, children)
    end

    def dispatch(variant, original)
      ast(
        :begin,
        ast(:if, ast(:send, ast(:const, ast(:cbase), :MutantRuntime), :active?, ast(:int, 1)), variant, original)
      )
    end

    it "strips its own dispatch down to the original branch" do
      original = ast(:send, ast(:send, nil, :a), :b)
      expect(synth.__send__(:unwrap, dispatch(ast(:nil), original))).to(eq(original))
    end

    it "strips nested dispatches all the way down" do
      original = ast(:send, nil, :a)
      # :false is the AST node type, not a boolean.
      nested = dispatch(ast(:nil), dispatch(ast(:false), original))
      expect(synth.__send__(:unwrap, nested)).to(eq(original))
    end

    # Not wrapped, two children, non-guard if, while, no condition, symbol, nil.
    def cases(plain, guard)
      [
        plain,
        ast(:begin, plain, plain),
        ast(:begin, ast(:if, ast(:send, nil, :ready?), plain, plain)),
        ast(:begin, ast(:while, guard, plain)),
        ast(:begin, ast(:if, nil, plain, plain)),
        ast(:sym, :x),
        nil
      ]
    end

    it "leaves anything that is not a dispatch exactly as it is" do
      plain = ast(:send, nil, :a)
      guard = ast(:send, ast(:const, ast(:cbase), :MutantRuntime), :active?, ast(:int, 1))
      cases(plain, guard).each { |node| expect(synth.__send__(:unwrap, node)).to(eq(node)) }
    end
  end

  describe "unparser round-trip fallback" do
    # From campfire: unparser can't round-trip the guarded inline-assignment
    # condition. Only that point should drop, not the whole file.
    let(:source) do
      <<~'RUBY'
        class DstrRepro
          def extract(response)
            if response.content_type && mime_type = Mime::Type.lookup(response.content_type)
              create! \
                io: StringIO.new(response.body), filename: "attachment.#{mime_type.symbol}", content_type: mime_type.to_s
            end
          end
        end
      RUBY
    end

    # Count, line and reason are all triage signal, so pin the exact message.
    def fallback
      registry = Kimera::RegistryScan.new.source(source, file: "dstr_repro.rb")
      result = nil
      expect { result = described_class.new(registry).synthesize("dstr_repro.rb", source) }
        .to(output(/dstr_repro\.rb: 1 mutation point\(s\) at line 3 are unguardable \(unparser round-trip\)/).to_stderr)
      [registry, result]
    end

    it "drops only the unguardable points and keeps the rest live", :aggregate_failures do
      registry, result = fallback
      expect([result.mutant_ids, result.skipped_unsafe])
        .to(satisfy { |(m, s)| !m.empty? && !s.empty? && !m.intersect?(s) })
      expect(result.mutant_ids.size + result.skipped_unsafe.size).to(eq(registry.count))
      expect { Unparser.parse(result.source) }.not_to(raise_error)
      dropped = registry.points.reject(&:safe?)
      expect(dropped.flat_map(&:ids)).to(eq(result.skipped_unsafe))
      expect(dropped.map(&:unsafe_reason).uniq).to(eq(["unmutatable: unparser could not round-trip its guard"]))
    end

    it "re-raises the original error when no point is guardable" do
      registry = Kimera::RegistryScan.new.source(source, file: "dstr_repro.rb")
      synth = described_class.new(registry)
      allow_any_instance_of(Kimera::Overlay::FileWeave).to(receive(:attempt).and_return(nil))
      expect { synth.synthesize("dstr_repro.rb", source) }
        .to(raise_error(StandardError, /Unparser cannot round trip|unparse/i))
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
      def unparse!
        allow(Unparser).to(receive(:unparse).and_wrap_original) do |original, node|
          unless %i[def defs].include?(node.type)
            raise(RuntimeError, "Could not find a round tripping solution for regexp")
          end
          original.call(node)
        end
      end

      def spliced
        registry = Kimera::RegistryScan.new.source(splice_source, file: "spliced.rb")
        unparse!
        result = nil
        expect { result = described_class.new(registry).synthesize("spliced.rb", splice_source) }
          .to(output(/spliced\.rb: file-level round-trip failed; 4 mutant\(s\) spliced per method/).to_stderr)
        [registry, result]
      end

      it "keeps every method's mutants and the untouched source verbatim", :aggregate_failures do
        registry, result = spliced
        expect(result.mutant_ids.size).to(eq(registry.count))
        expect(result.source).to(include("ODDITY = :unemittable"))
        expect(result.source).to(include("::MutantRuntime.active?"))
        expect(Prism.parse(result.source)).to(be_success)
      end

      def partial
        registry = Kimera::RegistryScan.new.source(splice_source, file: "spliced.rb")
        allow(Unparser).to(receive(:unparse).and_wrap_original) do |original, node|
          raise(RuntimeError, "boom") unless %i[def defs].include?(node.type)
          raise(RuntimeError, "boom") if node.children.first == :compare
          original.call(node)
        end
        result = nil
        expect { result = described_class.new(registry).synthesize("spliced.rb", splice_source) }
          .to(output(/2 mutant\(s\) spliced per method, 2 reported unmutatable/).to_stderr)
        [registry, result]
      end

      it "reports the points of a method it could not re-emit as unmutatable", :aggregate_failures do
        registry, result = partial
        expect(result.mutant_ids.size + result.skipped_unsafe.size).to(eq(registry.count))
        expect(result.mutant_ids & result.skipped_unsafe).to(be_empty)
        dropped = registry.points.select { |point| point.method_name.to_s == "compare" }
        expect(dropped.map(&:unsafe_reason).uniq).to(eq(["unmutatable: unparser could not round-trip its method"]))
        expect(registry.points.reject { |point| dropped.include?(point) }).to(all(be_safe))
      end

      # A rebuild failure outside any method is a Kimera bug. Splicing would hide it.
      def broken
        allow_any_instance_of(Kimera::Guardrail)
          .to(receive(:reopen).and_wrap_original) do |original, node|
            raise(NoMethodError, "undefined method 'children' for nil") if node.type == :casgn
            original.call(node)
          end
      end

      it "refuses to splice when the rebuild fails, rather than the emission" do
        registry = Kimera::RegistryScan.new.source(splice_source, file: "spliced.rb")
        synth = described_class.new(registry)
        broken
        expect { synth.synthesize("spliced.rb", splice_source) }.to(raise_error(NoMethodError))
      end

      def invalid!
        allow(Unparser).to(receive(:unparse).and_wrap_original) do |_original, node|
          unless %i[def defs].include?(node.type)
            raise(RuntimeError, "Could not find a round tripping solution for regexp")
          end
          "def broken(" # syntactically impossible splice
        end
      end

      it "refuses to splice a result that would not parse" do
        registry = Kimera::RegistryScan.new.source(splice_source, file: "spliced.rb")
        invalid!
        expect { described_class.new(registry).synthesize("spliced.rb", splice_source) }
          .to(raise_error(StandardError, /round tripping/))
      end

      def nested
        registry = Kimera::RegistryScan.new.source(nested_source, file: "nested.rb")
        unparse!
        [registry, described_class.new(registry).synthesize("nested.rb", nested_source)]
      end

      it "claims a nested definition's points once, for the outer method", :aggregate_failures do
        registry, result = nested
        expect(result.mutant_ids.size).to(eq(registry.count))
        expect(Prism.parse(result.source)).to(be_success)
        # Methods without points aren't re-emitted, so unparser can't normalise this.
        expect(result.source).to(include("def  untouched_by_points"))
      end

      def compiled
        registry = Kimera::RegistryScan.new.source(splice_source, file: "spliced.rb")
        unparse!
        mod = Module.new
        mod.module_eval(described_class.new(registry).synthesize("spliced.rb", splice_source).source)
        [mod.const_get(:Spliced), registry.each.find { |m, _p| m.label == "> => <" }.first]
      end

      it "still selects a spliced mutant at runtime", :aggregate_failures do
        klass, flip = compiled
        expect(klass.new.compare(2, 1)).to(be(true))
        Kimera::Runtime.active = flip.id
        expect(klass.new.compare(2, 1)).to(be(false))
      end

      def reopened
        registry = Kimera::RegistryScan.new.source(value_source, file: "value.rb")
        unparse!
        source = nil
        announced = /value\.rb: file-level round-trip failed; #{registry.count} mutant\(s\) spliced per method/
        expect { source = described_class.new(registry).synthesize("value.rb", value_source).source }
          .to(output(announced).to_stderr)
        [registry, source]
      end

      it "reopens value-object constants instead of redefining them", :aggregate_failures do
        registry, source = reopened
        stub_const("Spliced", Module.new)
        stub_const("SplicedTop", nil)
        Kimera::Warnings.silence { TOPLEVEL_BINDING.eval(value_source) }
        before = [Spliced::Point.new(x: 11), SplicedTop.new(20), Spliced::Nested.new(x: 10)]
        Kimera::Warnings.silence { TOPLEVEL_BINDING.eval(source) }
        expect([Spliced::Point, SplicedTop, Spliced::Nested]).to(eq(before.map(&:class)))
        flip = ->(label, line) { registry.each.find { |m, p| m.label == label && p.location.start_line == line }.first }
        Kimera::Runtime.active = flip.call("> => <", 3).id
        expect(before[0].big?).to(be(false))
        Kimera::Runtime.active = flip.call("< => >", 5).id
        expect(before[1].small?).to(be(true))
        Kimera::Runtime.active = flip.call("== => !=", 7).id
        expect(before[2].same?).to(be(false))
      end

      it "reopens with the constant's own scope, or the lexical one" do
        _registry, source = reopened
        lexical = "(is_a?(::Module) ? self : ::Object)"
        point = "Point = (#{lexical}.const_defined?(:Point, false) ? #{lexical}.const_get(:Point) : " \
          "Data.define(:x)); Point.class_eval do"
        top = "::SplicedTop = (::Object.const_defined?(:SplicedTop, false) ? ::Object.const_get(:SplicedTop) : " \
          "Struct.new(:x)); ::SplicedTop.class_eval {"
        nested = "Spliced::Nested = (Spliced.const_defined?(:Nested, false) ? Spliced.const_get(:Nested) : " \
          "Data.define(:x)); Spliced::Nested.class_eval do"
        other = "Other = (#{lexical}.const_defined?(:Other, false) ? #{lexical}.const_get(:Other) : " \
          "Class.new); Other.class_eval {"
        expect(source).to(include(point, top, nested, other))
      end

      it "leaves every other assignment as written", :aggregate_failures do
        _registry, source = reopened
        expect(source).to(include("Plain = Data.define(:x)\n", "Callback = proc { :noop }"))
        expect(source).to(include("Safe = Data&.define(:x) do", "helper = Struct.new(:y) {"))
      end

      it "leaves a file with nothing to splice unreopened" do
        src = "Point = Data.define(:x) do\n  def big? = x > 10\nend\n"
        registry = Kimera::RegistryScan.new.source(src, file: "p.rb")
        allow(Unparser).to(receive(:unparse).and_raise(RuntimeError, "Could not find a round tripping solution"))
        expect { described_class.new(registry).synthesize("p.rb", src) }.to(raise_error(RuntimeError, /round tripping/))
      end
    end

    # giacope/kimera#7: a string interpolating a pattern binding sank every
    # mutant in the file, including ones in unrelated methods.
    it "weaves a file whose strings interpolate a case/in binding", :aggregate_failures do
      src = <<~'RUBY'
        class PatternBid
          def big?(value) = value > 10

          def bid(input)
            case input
            in [:parsed, chosen] then ["#{input.first} #{chosen}", chosen]
            end
          end
        end
      RUBY
      registry = Kimera::RegistryScan.new.source(src, file: "bid.rb")
      result = nil
      expect { result = described_class.new(registry).synthesize("bid.rb", src) }.not_to(output.to_stderr)
      expect(result.mutant_ids.size).to(eq(registry.count))
      mod = Module.new
      mod.module_eval(result.source)
      expect(mod.const_get(:PatternBid).new.bid([:parsed, 2])).to(eq(["parsed 2", 2]))
    end

    it "does not warn when every point is guardable" do
      src = "def m(a, b)\n  a > b\nend\n"
      registry = Kimera::RegistryScan.new.source(src, file: "clean.rb")
      expect { described_class.new(registry).synthesize("clean.rb", src) }.not_to(output.to_stderr)
    end
  end
end
