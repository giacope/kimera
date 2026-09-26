# frozen_string_literal: true

require "kimera/operators"
require "kimera/registry/builder"
require "kimera/runtime"
require "kimera/synthesis/overlay"

# Each family also runs live, since one variant rendering bad source breaks the whole file's overlay.
RSpec.describe("extended operators") do
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

  def with_overlay(key)
    catalog = built(key)
    verbose = $VERBOSE

    $VERBOSE = nil
    TOPLEVEL_BINDING.eval(Kimera::Overlay.new(catalog).synthesize("ext_ops.rb", ext_source).source, "ext_ops.rb")
    $VERBOSE = verbose
    yield(catalog.each.to_h { |m, _p| [m.label, m.id] }, catalog)
  ensure
    Kimera::Runtime.reset!
    Object.__send__(:remove_const, :ExtOps) if defined?(ExtOps)
  end

  def active(id)
    Kimera::Runtime.active = id
    yield
  ensure
    Kimera::Runtime.active = nil
  end

  it "arithmetic swaps binary operators", :aggregate_failures do
    expect(labels("arithmetic")).to(include("+ => -"))
    with_overlay("arithmetic") do |ids|
      object = ExtOps.new
      expect(object.add(4, 2)).to(eq(6))
      active(ids.fetch("+ => -")) { expect(object.add(4, 2)).to(eq(2)) }
    end
  end

  it "negation deletes the bang", :aggregate_failures do
    with_overlay("negation") do |ids|
      object = ExtOps.new
      expect(object.negate(true)).to(be(false))
      active(ids.fetch("delete !")) { expect(object.negate(true)).to(be(true)) }
    end
  end

  it "safe_navigation strengthens &. to .", :aggregate_failures do
    with_overlay("safe_navigation") do |ids|
      object = ExtOps.new
      expect(object.safe_len(nil)).to(be_nil)
      active(ids.fetch("&. => .")) do
        expect { object.safe_len(nil) }.to(raise_error(NoMethodError))
      end
    end
  end

  it "conditional pins the predicate to true or false", :aggregate_failures do
    expect(labels("conditional")).to(contain_exactly("condition => true", "condition => false"))
    with_overlay("conditional") do |ids|
      object = ExtOps.new
      expect(object.pick(true)).to(eq(:yes))
      active(ids.fetch("condition => false")) { expect(object.pick(true)).to(eq(:no)) }
      active(ids.fetch("condition => true")) { expect(object.pick(false)).to(eq(:yes)) }
    end
  end

  it "skips elsif arms (not a wrappable expression)" do
    src = <<~RUBY
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
    catalog = Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: ["conditional"]))
      .source(src, file: "route.rb")
    # Only the outer if contributes; the elsif arm is skipped.
    expect(catalog.each.count).to(eq(2))
  end

  it "numeric_literal perturbs integers with the off-by-one pair and zero", :aggregate_failures do
    expect(labels("numeric_literal")).to(include("10 => 9", "10 => 11", "10 => 0"))
    one = Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: ["numeric_literal"]))
      .source("def m\n  1\nend\n", file: "one.rb")
    expect(one.each.map { |m, _p| m.label }).to(contain_exactly("1 => 0", "1 => 2"))
    with_overlay("numeric_literal") do |ids|
      object = ExtOps.new
      expect(object.limit).to(eq(10))
      active(ids.fetch("10 => 0")) { expect(object.limit).to(eq(0)) }
      active(ids.fetch("10 => 11")) { expect(object.limit).to(eq(11)) }
    end
  end

  it "string_literal empties non-empty strings", :aggregate_failures do
    with_overlay("string_literal") do |ids|
      object = ExtOps.new
      expect(object.greeting).to(eq("hello"))
      active(ids.fetch('"hello" => ""')) { expect(object.greeting).to(eq("")) }
    end
  end

  it "collection_literal empties arrays and hashes", :aggregate_failures do
    with_overlay("collection_literal") do |ids|
      object = ExtOps.new
      expect(object.pair).to(eq([1, 2]))
      active(ids.fetch("array => []")) { expect(object.pair).to(eq([])) }
    end
  end

  it "range flips inclusivity", :aggregate_failures do
    with_overlay("range") do |ids|
      object = ExtOps.new
      expect(object.span.to_a).to(eq([2, 3, 4, 5]))
      active(ids.fetch(".. => ...")) { expect(object.span.to_a).to(eq([2, 3, 4])) }
    end
  end

  it "method_unwrap removes a transformation call", :aggregate_failures do
    with_overlay("method_unwrap") do |ids|
      object = ExtOps.new
      expect(object.tidy(" x ")).to(eq("x"))
      active(ids.fetch("delete .strip")) { expect(object.tidy(" x ")).to(eq(" x ")) }
    end
  end

  it "return_value nils explicit returns and non-call tails", :aggregate_failures do
    with_overlay("return_value") do |ids, catalog|
      object = ExtOps.new
      expect(object.evens([1, 2, 3])).to(eq([2]))
      active(ids.fetch("return => return nil")) { expect(object.evens([1, 2])).to(be_nil) }
      # Looked up by source: several methods have a "tail => nil" mutant.
      mutant = catalog.each.find { |_m, p| p.original_source == "a * b" }.first.id
      expect(object.total(3, 4)).to(eq(12))
      active(mutant) { expect(object.total(3, 4)).to(be_nil) }
    end
  end

  it "return_value skips bare `return`, `return nil`, and identifier-call tails" do
    src = <<~RUBY
      def a = (return)
      def b = (return nil)
      def c(x)
        x.compute
      end
    RUBY
    catalog = Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: ["return_value"]))
      .source(src, file: "r.rb")
    expect(catalog.each.count).to(eq(0))
  end

  it "selector_swap swaps predicate duals, preserving blocks", :aggregate_failures do
    with_overlay("selector_swap") do |ids|
      object = ExtOps.new
      expect(object.evens([1, 2, 3])).to(eq([2]))
      active(ids.fetch("select => reject")) { expect(object.evens([1, 2, 3])).to(eq([1, 3])) }
    end
  end

  it "regexp replaces the pattern with match-all and match-none extremes", :aggregate_failures do
    with_overlay("regexp") do |ids|
      object = ExtOps.new
      expect(object.code?("ABC")).to(be(true))
      expect(object.code?("ab")).to(be(false))
      active(ids.fetch("regexp => // (match all)")) { expect(object.code?("ab")).to(be(true)) }
      active(ids.fetch("regexp => /(?!)/ (match none)")) { expect(object.code?("ABC")).to(be(false)) }
    end
  end

  it "element_drop removes one element at a time from multi-element literals", :aggregate_failures do
    with_overlay("element_drop") do |ids|
      object = ExtOps.new
      expect(object.pair).to(eq([1, 2]))
      active(ids.fetch("drop `1`")) { expect(object.pair).to(eq([2])) }
      active(ids.fetch("drop `2`")) { expect(object.pair).to(eq([1])) }
    end
  end

  it "element_drop skips single-element and splatted literals" do
    src = "def m(rest)\n  a = [1]\n  b = [2, *rest]\n  [a, b]\nend\n"
    catalog = Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: ["element_drop"]))
      .source(src, file: "e.rb")
    expect(catalog.each.map { |m, _p| m.label }).to(contain_exactly("drop `a`", "drop `b`"))
  end

  it "argument_drop removes one positional argument at a time", :aggregate_failures do
    with_overlay("argument_drop") do |ids|
      object = ExtOps.new
      expect(object.pad("ab")).to(eq("ab..."))
      active(ids.fetch('drop arg `"."`')) { expect(object.pad("ab")).to(eq("ab   ")) }
    end
  end

  it "op_assign swaps the compound-assignment operator", :aggregate_failures do
    with_overlay("op_assign") do |ids|
      object = ExtOps.new
      expect(object.bump(10)).to(eq(13))
      active(ids.fetch("+= => -=")) { expect(object.bump(10)).to(eq(7)) }
    end
  end

  it "dedups identical directives across operators (permit vs argument_drop)" do
    src = "def user_params\n  params.permit(:name, :admin)\nend\n"
    catalog = Kimera::RegistryScan.new(
      operators: Kimera::Operators.build(keys: %w[rails_permit argument_drop])
    ).source(src, file: "p.rb")
    # The more specific rails label wins.
    expect(catalog.each.map { |m, _p| m.label }).to(contain_exactly("permit: drop :name", "permit: drop :admin"))
  end

  # The only family that mutates mid-expression, so it is checked on rendered source.
  describe "chain_link_deletion" do
    def chained(src)
      Kimera::RegistryScan.new(
        operators: Kimera::Operators.build(keys: ["chain_link_deletion"])
      ).source(src, file: "chain.rb")
    end

    def rendered(catalog)
      catalog.each.map do |m, p|
        Kimera::Rewrite::Directive.render(p.original_source, m.directive)
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

    it "rewrites a live chain when the mutant is selected", :aggregate_failures do
      src = <<~RUBY
        class ChainDemo
          def evens_then_first(xs)
            xs.select(&:even?).sort.first
          end
        end
      RUBY
      catalog = chained(src)
      result = Kimera::Overlay.new(catalog).synthesize("chain.rb", src)
      Kimera::Overlay.evaluate(result.source, "chain.rb")
      ids = catalog.each.to_h { |m, _p| [m.label, m.id] }
      object = ChainDemo.new

      expect(object.evens_then_first([4, 2, 3])).to(eq(2))
      active(ids.fetch("drop chain link `.sort`")) do
        expect(object.evens_then_first([4, 2, 3])).to(eq(4))
      end
      active(ids.fetch("drop chain link `.select`")) do
        expect(object.evens_then_first([4, 2, 3])).to(eq(2))
      end
    ensure
      Kimera::Runtime.reset!
      Object.__send__(:remove_const, :ChainDemo) if defined?(ChainDemo)
    end
  end

  it "method_unwrap skips calls with arguments or blocks" do
    src = <<~RUBY
      def work(xs)
        xs.sort { |a, b| a <=> b }
        xs.to_s(2)
        xs.uniq
      end
    RUBY
    catalog = Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: ["method_unwrap"]))
      .source(src, file: "work.rb")
    expect(catalog.each.map { |m, _p| m.label }).to(eq(["delete .uniq"]))
  end
end
