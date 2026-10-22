# frozen_string_literal: true

require "kimera/operators"
require "kimera/registry/builder"
require "kimera/runtime"
require "kimera/support/warnings"
require "kimera/synthesis/overlay"

# Each family also runs live, since one variant rendering bad source breaks the whole file's overlay.
RSpec.describe(Kimera::Operators) do
  let(:ext_source) { <<~RUBY }
    class ExtOps
      def add(a, b)
        a + b
      end

      def negate(x)
        !x
      end

      def safe_len(s)
        s&.length
      end

      def pick(flag)
        flag ? :yes : :no
      end

      def limit
        10
      end

      def greeting
        "hello"
      end

      def pair
        [1, 2]
      end

      def span
        (2..5)
      end

      def tidy(s)
        s.strip
      end

      def evens(xs)
        result = xs.select(&:even?)
        return result
      end

      def code?(s)
        s.match?(/[A-Z]{3}/)
      end

      def total(a, b)
        a * b
      end

      def pad(s)
        s.ljust(5, ".")
      end

      def bump(t)
        t += 3
        t
      end
    end
  RUBY

  def built(key)
    Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: [key])).source(ext_source, file: "ext_ops.rb")
  end

  def labels(key)
    built(key).each.map { |m, _p| m.label }
  end

  def scan(keys, code, file)
    Kimera::RegistryScan.new(operators: described_class.build(keys: Array(keys))).source(code, file: file)
  end

  def evaluated(catalog, code, file)
    synthesized = Kimera::Overlay.new(catalog).synthesize(file, code)
    Kimera::Overlay::Source.new(synthesized.source).evaluate(file)
  end

  def pick(catalog, wanted) = catalog.each.find { |m, p| m.label == wanted || p.original_source == wanted }.first.id

  # What the block answers for an ExtOps under the key's overlay, with the
  # mutant of that label (or source) active, or none.
  def under(key, wanted = nil)
    stub_const("ExtOps", Class.new)
    catalog = built(key)
    overlay = Kimera::Overlay.new(catalog).synthesize("ext_ops.rb", ext_source)
    Kimera::Warnings::SILENCED.during { TOPLEVEL_BINDING.eval(overlay.source, "ext_ops.rb") }
    active(wanted && pick(catalog, wanted)) { yield(ExtOps.new) }
  end

  # The block's answer with no mutant active, then with the wanted one.
  def outcomes(key, wanted, &) = [under(key, &), under(key, wanted, &)]

  def active(id, &) = Kimera::RUNTIME.during(id, &)

  it "arithmetic swaps binary operators", :aggregate_failures do
    expect(labels("arithmetic")).to(include("+ => -"))
    expect(outcomes("arithmetic", "+ => -") { |o| o.add(4, 2) }).to(eq([6, 2]))
  end

  it "negation deletes the bang" do
    expect(outcomes("negation", "delete !") { |o| o.negate(true) }).to(eq([false, true]))
  end

  it "safe_navigation strengthens &. to .", :aggregate_failures do
    expect(under("safe_navigation") { |o| o.safe_len(nil) }).to(be_nil)
    expect { under("safe_navigation", "&. => .") { |o| o.safe_len(nil) } }.to(raise_error(NoMethodError))
  end

  it "conditional pins the predicate to true or false", :aggregate_failures do
    expect(labels("conditional")).to(contain_exactly("condition => true", "condition => false"))
    expect(outcomes("conditional", "condition => false") { |o| o.pick(true) }).to(eq(%i[yes no]))
    expect(under("conditional", "condition => true") { |o| o.pick(false) }).to(eq(:yes))
  end

  # `if page = next_page` binds page for the body: pinning the predicate to
  # a bare literal dropped the binding, and with it the whole point, since
  # unparser cannot write the body's read of a local no longer assigned.
  # A predicate that binds nothing is still not evaluated.
  describe "conditional on a predicate that assigns" do
    let(:linker) { <<~RUBY }
      class Linker
        def link(pages)
          if pages.any? && (page = pages.shift)
            "<\#{page}>"
          end
        end

        def skip(pages)
          :next if pages.shift
        end
      end
    RUBY

    # The overlay, and each mutant's id by method and label.
    def linked
      stub_const("Linker", Class.new)
      catalog = scan("conditional", linker, "linker.rb")
      result = Kimera::Overlay.new(catalog).synthesize("linker.rb", linker)
      TOPLEVEL_BINDING.eval(result.source, "linker.rb")
      [result, catalog.each.to_h { |m, p| [[p.method_name, m.label], m.id] }]
    end

    it "is overlaid, not skipped as unsafe" do
      expect(linked.first.skipped_unsafe).to(be_empty)
    end

    it "keeps the assignment when pinned true" do
      _, ids = linked
      expect(active(ids.fetch(["link", "condition => true"])) { Linker.new.link([]) }).to(eq("<>"))
    end

    it "still makes the assignment when pinned false", :aggregate_failures do
      _, ids = linked
      pages = [1, 2]
      expect(active(ids.fetch(["link", "condition => false"])) { Linker.new.link(pages) }).to(be_nil)
      expect(pages).to(eq([2]))
    end

    it "does not evaluate a predicate that binds nothing", :aggregate_failures do
      _, ids = linked
      pages = [1, 2]
      expect(active(ids.fetch(["skip", "condition => true"])) { Linker.new.skip(pages) }).to(eq(:next))
      expect(pages).to(eq([1, 2]))
    end
  end

  it "skips elsif arms (not a wrappable expression)" do
    code = <<~RUBY
      def route(x)
        if x == 1
          :one
        elsif x == 2
          :two
        else
          :many
        end
      end
    RUBY
    catalog = Kimera::RegistryScan.new(operators: described_class.build(keys: ["conditional"]))
      .source(code, file: "route.rb")
    # Only the outer if contributes; the elsif arm is skipped.
    expect(catalog.each.count).to(eq(2))
  end

  it "numeric_literal perturbs integers with the off-by-one pair and zero" do
    expect(labels("numeric_literal")).to(include("10 => 9", "10 => 11", "10 => 0"))
  end

  it "numeric_literal perturbs one to zero and two" do
    one = Kimera::RegistryScan.new(operators: described_class.build(keys: ["numeric_literal"]))
      .source("def m\n  1\nend\n", file: "one.rb")
    expect(one.each.map { |m, _p| m.label }).to(contain_exactly("1 => 0", "1 => 2"))
  end

  it "numeric_literal runs live" do
    limits = [nil, "10 => 0", "10 => 11"].map { |label| under("numeric_literal", label, &:limit) }
    expect(limits).to(eq([10, 0, 11]))
  end

  it "string_literal empties non-empty strings" do
    expect(outcomes("string_literal", '"hello" => ""', &:greeting)).to(eq(["hello", ""]))
  end

  it "collection_literal empties arrays and hashes" do
    expect(outcomes("collection_literal", "array => []", &:pair)).to(eq([[1, 2], []]))
  end

  it "range flips inclusivity" do
    expect(outcomes("range", ".. => ...") { |o| o.span.to_a }).to(eq([[2, 3, 4, 5], [2, 3, 4]]))
  end

  it "method_unwrap removes a transformation call" do
    expect(outcomes("method_unwrap", "delete .strip") { |o| o.tidy(" x ") }).to(eq(["x", " x "]))
  end

  it "return_value nils explicit returns" do
    expect(outcomes("return_value", "return => return nil") { |o| o.evens([1, 2]) }).to(eq([[2], nil]))
  end

  # Looked up by source: several methods have a "tail => nil" mutant.
  it "return_value nils non-call tails" do
    expect(outcomes("return_value", "a * b") { |o| o.total(3, 4) }).to(eq([12, nil]))
  end

  it "return_value skips bare `return`, `return nil`, and identifier-call tails" do
    code = <<~RUBY
      def a = (return)
      def b = (return nil)
      def c(x)
        x.compute
      end
    RUBY
    catalog = Kimera::RegistryScan.new(operators: described_class.build(keys: ["return_value"]))
      .source(code, file: "r.rb")
    expect(catalog.each.count).to(eq(0))
  end

  it "selector_swap swaps predicate duals, preserving blocks" do
    expect(outcomes("selector_swap", "select => reject") { |o| o.evens([1, 2, 3]) }).to(eq([[2], [1, 3]]))
  end

  it "regexp matches its pattern with no mutant active" do
    expect(under("regexp") { |o| [o.code?("ABC"), o.code?("ab")] }).to(eq([true, false]))
  end

  it "regexp's match-all extreme matches anything" do
    expect(under("regexp", "regexp => // (match all)") { |o| o.code?("ab") }).to(be(true))
  end

  it "regexp's match-none extreme matches nothing" do
    expect(under("regexp", "regexp => /(?!)/ (match none)") { |o| o.code?("ABC") }).to(be(false))
  end

  it "element_drop removes one element at a time from multi-element literals" do
    pairs = [nil, "drop `1`", "drop `2`"].map { |label| under("element_drop", label, &:pair) }
    expect(pairs).to(eq([[1, 2], [2], [1]]))
  end

  it "element_drop skips single-element and splatted literals" do
    code = "def m(rest)\n  a = [1]\n  b = [2, *rest]\n  [a, b]\nend\n"
    catalog = Kimera::RegistryScan.new(operators: described_class.build(keys: ["element_drop"]))
      .source(code, file: "e.rb")
    expect(catalog.each.map { |m, _p| m.label }).to(contain_exactly("drop `a`", "drop `b`"))
  end

  it "argument_drop removes one positional argument at a time" do
    expect(outcomes("argument_drop", 'drop arg `"."`') { |o| o.pad("ab") }).to(eq(["ab...", "ab   "]))
  end

  it "op_assign swaps the compound-assignment operator" do
    expect(outcomes("op_assign", "+= => -=") { |o| o.bump(10) }).to(eq([13, 7]))
  end

  it "dedups identical directives across operators (permit vs argument_drop)" do
    code = "def user_params\n  params.permit(:name, :admin)\nend\n"
    catalog = Kimera::RegistryScan.new(
      operators: described_class.build(keys: %w[rails_permit argument_drop])
    ).source(code, file: "p.rb")
    # The more specific rails label wins.
    expect(catalog.each.map { |m, _p| m.label }).to(contain_exactly("permit: drop :name", "permit: drop :admin"))
  end

  # The only family that mutates mid-expression, so it is checked on rendered source.
  describe "chain_link_deletion" do
    def chained(code)
      Kimera::RegistryScan.new(
        operators: Kimera::Operators.build(keys: ["chain_link_deletion"])
      ).source(code, file: "chain.rb")
    end

    def rendered(catalog)
      catalog.each.map do |m, p|
        Kimera::Rewrite::Directive.new(m.directive).render(p.original_source)
      end
    end

    it "drops each intermediate link, keeping the head and the tail", :aggregate_failures do
      catalog = chained(<<~RUBY)
        def touch(uris)
          Status.where(uri: uris).should_fetch_replies.touch_all(:fetched_at)
        end
      RUBY

      expect(catalog.each.map { |m, _p| m.label })
        .to(
          contain_exactly(
            "drop chain link `.should_fetch_replies`",
            "drop chain link `.where`"
          )
        )
      expect(rendered(catalog)).to(include("Status.where(uri: uris).touch_all(:fetched_at)"))
    end

    it "leaves the root of a chain alone (that is method_unwrap's job)", :aggregate_failures do
      # A receiverless call is still a CallNode; only the receiver check rules it out.
      expect(chained("def m(x)\n  x.strip\nend\n").each.count).to(eq(0))
      expect(chained("def m\n  source.strip\nend\n").each.count).to(eq(0))
    end

    it "skips a link carrying a block, and drops one past it" do
      catalog = chained("def m(xs)\n  xs.map { |x| x }.first.to_s\nend\n")

      expect(catalog.each.map { |m, _p| m.label }).to(eq(["drop chain link `.first`"]))
    end

    it "leaves operator-named links to their own families" do
      # `xs[0]` is a CallNode with a receiver; only the identifier check skips it.
      expect(chained("def m(xs)\n  xs[0].to_s\nend\n").each.count).to(eq(0))
    end

    describe "on a live chain" do
      let(:demo) { <<~RUBY }
        class ChainDemo
          def evens_then_first(xs)
            xs.select(&:even?).sort.first
          end
        end
      RUBY

      # The chain's answer, with the labelled mutant active, or none.
      def demoed(label = nil)
        stub_const("ChainDemo", Class.new)
        catalog = chained(demo)
        evaluated(catalog, demo, "chain.rb")
        active(label && pick(catalog, label)) { ChainDemo.new.evens_then_first([4, 2, 3]) }
      end

      it "drops the selected link" do
        expect([demoed, demoed("drop chain link `.sort`"), demoed("drop chain link `.select`")]).to(eq([2, 4, 2]))
      end
    end
  end

  it "method_unwrap skips calls with arguments or blocks" do
    code = <<~RUBY
      def work(xs)
        xs.sort { |a, b| a <=> b }
        xs.to_s(2)
        xs.uniq
      end
    RUBY
    catalog = Kimera::RegistryScan.new(operators: described_class.build(keys: ["method_unwrap"]))
      .source(code, file: "work.rb")
    expect(catalog.each.map { |m, _p| m.label }).to(eq(["delete .uniq"]))
  end
end
