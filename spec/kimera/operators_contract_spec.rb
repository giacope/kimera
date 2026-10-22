# frozen_string_literal: true

require "kimera/operators"
require "kimera/registry/builder"
require "kimera/runtime"
require "kimera/synthesis/overlay"

# Each family is checked in the registry, a live overlay, and baked source.
# default_argument bakes and overlays by different mechanisms.
RSpec.describe(Kimera::Operators) do
  let(:contract_src) { <<~RUBY }
    class Contracts
      def lookup(h, k)
        h[k]
      end

      def norm(x)
        Array(x)
      end

      def duck(x)
        x.respond_to?(:each)
      end

      def tag
        :ok
      end

      def greet(name = "world", punct: "!")
        "hi \#{name}\#{punct}"
      end

      def compact(xs)
        xs.filter_map { |x| x }
      end
    end
  RUBY

  def scan(keys, code = contract_src, file = "contracts.rb")
    Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: Array(keys))).source(code, file: file)
  end

  def built(key) = scan(key)

  def labels(key)
    built(key).each.map { |m, _p| m.label }
  end

  def overlaid(catalog, code, file)
    synthesized = Kimera::Overlay.new(catalog).synthesize(file, code)
    Kimera::Overlay::Source.new(synthesized.source).evaluate(File.expand_path(file))
  end

  # What the block answers for a Contracts under the key's overlay, with the
  # labelled mutant active, or none.
  def under(key, label = nil)
    stub_const("Contracts", Class.new)
    catalog = built(key)
    overlaid(catalog, contract_src, "contracts.rb")
    id = label && catalog.each.to_h { |m, _p| [m.label, m.id] }.fetch(label)
    active(id) { yield(Contracts.new) }
  ensure
    Kimera::RUNTIME.reset!
  end

  def active(id)
    Kimera::RUNTIME.active = id
    yield
  ensure
    Kimera::RUNTIME.active = nil
  end

  def contract_keys = %w[index_fetch kernel_coercion respond_to_guard symbol_literal default_argument]

  describe "index_fetch" do
    it "has one label" do
      expect(labels("index_fetch")).to(eq(["[] => fetch"]))
    end

    it "leaves a hit and a tolerated miss alone with no mutant active" do
      expect(under("index_fetch") { |o| [o.lookup({ a: 1 }, :a), o.lookup({ a: 1 }, :nope)] }).to(eq([1, nil]))
    end

    it "still answers a hit" do
      expect(under("index_fetch", "[] => fetch") { |o| o.lookup({ a: 1 }, :a) }).to(eq(1))
    end

    it "turns a tolerated miss into a KeyError" do
      expect { under("index_fetch", "[] => fetch") { |o| o.lookup({ a: 1 }, :nope) } }.to(raise_error(KeyError))
    end

    it "carries the bare directive and skips writes, multi-index reads and splats", :aggregate_failures do
      m = built("index_fetch").each.first.first
      expect(m.directive).to(eq("type" => "index_to_fetch"))

      code = <<~RUBY
        def m(h, a, keys)
          h[:k] = 1
          a[1, 2]
          h[*keys]
          h[:k]
        end
      RUBY
      catalog = Kimera::RegistryScan.new(operators: described_class.build(keys: ["index_fetch"]))
        .source(code, file: "i.rb")
      expect(catalog.each.map { |_mutant, point| point.original_source }).to(eq(["h[:k]"]))
    end

    it "rejects a block form, which is not a plain read" do
      blocked = Kimera::RegistryScan.new(operators: described_class.build(keys: ["index_fetch"]))
        .source("def m(h, k)\n  h[k] { |x| x }\nend\n", file: "i.rb")
      expect(blocked.each.count).to(eq(0))
    end

    describe "on the explicit and safe-navigated spellings" do
      let(:spellings) { <<~RUBY }
        class Spellings
          def explicit(h, k)
            h.[](k)
          end

          def maybe(h, k)
            h&.[](k)
          end
        end
      RUBY

      # What the block answers for a Spellings, with the mutant of the point
      # whose source is given active, or none.
      def spelled(source)
        stub_const("Spellings", Class.new)
        catalog = scan("index_fetch", spellings, "spellings.rb")
        overlaid(catalog, spellings, "spellings.rb")
        id = source && catalog.each.to_h { |m, p| [p.original_source, m.id] }.fetch(source)
        active(id) { yield(Spellings.new) }
      ensure
        Kimera::RUNTIME.reset!
      end

      it "rewrites both, preserving &." do
        catalog = scan("index_fetch", spellings, "spellings.rb")
        sources = catalog.each.map { |m, p| Kimera::Rewrite::Directive.new(m.directive).render(p.original_source) }
        expect(sources).to(contain_exactly("h.fetch(k)", "h&.fetch(k)"))
      end

      it "tolerates a miss and nil with no mutant active" do
        expect(spelled(nil) { |o| [o.explicit({ a: 1 }, :nope), o.maybe(nil, :k)] }).to(eq([nil, nil]))
      end

      it "raises on a miss through the explicit spelling" do
        expect { spelled("h.[](k)") { |o| o.explicit({ a: 1 }, :nope) } }.to(raise_error(KeyError))
      end

      # Dropping `&.` too would mutate nil- and miss-tolerance at once, so a survivor is unattributable.
      it "keeps nil tolerance through the safe-navigated spelling" do
        expect(spelled("h&.[](k)") { |o| o.maybe(nil, :k) }).to(be_nil)
      end

      it "raises on a miss through the safe-navigated spelling" do
        expect { spelled("h&.[](k)") { |o| o.maybe({ a: 1 }, :nope) } }.to(raise_error(KeyError))
      end
    end
  end

  describe "kernel_coercion" do
    it "has one label" do
      expect(labels("kernel_coercion")).to(eq(["delete Array()"]))
    end

    it "normalizes nil with no mutant active" do
      expect(under("kernel_coercion") { |o| o.norm(nil) }).to(eq([]))
    end

    it "drops the normalization, exposing what the argument really is" do
      expect(under("kernel_coercion", "delete Array()") { |o| o.norm(nil) }).to(be_nil)
    end

    it "skips a receiver'd call, a block, and multi-argument Integer()" do
      code = <<~RUBY
        def m(x, s)
          Foo.Array(x)
          Integer(s, 16)
          Array(x) { |e| e }
          String(x)
        end
      RUBY
      catalog = Kimera::RegistryScan.new(operators: described_class.build(keys: ["kernel_coercion"]))
        .source(code, file: "k.rb")
      expect(catalog.each.map { |m, _p| m.label }).to(eq(["delete String()"]))
    end

    # `Array(*xs)` does not unwrap to a single value.
    it "rejects a splatted argument" do
      catalog = Kimera::RegistryScan.new(operators: described_class.build(keys: ["kernel_coercion"]))
        .source("def m(xs)\n  Array(*xs)\nend\n", file: "k.rb")
      expect(catalog.each.count).to(eq(0))
    end
  end

  describe "respond_to_guard" do
    it "has one label" do
      expect(labels("respond_to_guard")).to(eq(["delete .respond_to?"]))
    end

    it "answers the duck-type check with no mutant active" do
      expect(under("respond_to_guard") { |o| [o.duck([1]), o.duck(1)] }).to(eq([true, false]))
    end

    it "collapses the duck-type check to the receiver's own truthiness" do
      expect(under("respond_to_guard", "delete .respond_to?") { |o| o.duck(1) }).to(eq(1))
    end

    it "accepts the private-methods arity but not a computed method name" do
      code = <<~RUBY
        def m(x, name)
          x.respond_to?(:size, true)
          x.respond_to?(name)
        end
      RUBY
      catalog = Kimera::RegistryScan.new(operators: described_class.build(keys: ["respond_to_guard"]))
        .source(code, file: "r.rb")
      expect(catalog.each.map { |_m, p| p.original_source }).to(eq(["x.respond_to?(:size, true)"]))
    end

    it "matches only a receiver'd, blockless respond_to? of arity 1..2" do
      {
        "another selector" => "def m(x)\n  x.respond_to_missing?(:a)\nend\n",
        "receiverless" => "def m\n  respond_to?(:a)\nend\n",
        "block form" => "def m(x)\n  x.respond_to?(:a) { |y| y }\nend\n",
        "over-arity" => "def m(x)\n  x.respond_to?(:a, true, 1)\nend\n"
      }.each do |name, code|
        catalog = Kimera::RegistryScan.new(operators: described_class.build(keys: ["respond_to_guard"]))
          .source(code, file: "r.rb")
        expect(catalog.each.count).to(eq(0), "#{name} should not match")
      end
    end
  end

  describe "symbol_literal" do
    it "keeps the symbol with no mutant active" do
      expect(under("symbol_literal", &:tag)).to(eq(:ok))
    end

    it "renames a symbol so any name-identity dependency breaks" do
      expect(under("symbol_literal", ":ok => :ok__kimera__", &:tag)).to(eq(:ok__kimera__))
    end

    # A label (`tier:`) has no parser-side node, so it would report no_coverage forever.
    it "skips label position but keeps every expression spelling", :aggregate_failures do
      code = <<~RUBY
        def m(o)
          o.f(tier: 1)
          {gold: 1, :silver => 2, "bronze": 3}
          %i[copper]
          o.send(:tin)
        end
      RUBY
      catalog = Kimera::RegistryScan.new(operators: described_class.build(keys: ["symbol_literal"]))
        .source(code, file: "s.rb")
      expect(catalog.each.map { |_m, p| p.original_source }).to(contain_exactly(":silver", "copper", ":tin"))

      result = Kimera::Overlay.new(catalog).synthesize("s.rb", code)
      expect(result.mutant_ids.size).to(eq(catalog.each.count))
    end

    it "carries the renamed value and leaves an empty symbol alone", :aggregate_failures do
      m = built("symbol_literal").each.find { |mu, _p| mu.label.start_with?(":ok") }.first
      expect(m.directive).to(eq("type" => "symbol_literal", "value" => "ok__kimera__"))

      catalog = Kimera::RegistryScan.new(operators: described_class.build(keys: ["symbol_literal"]))
        .source("def m\n  :\"\"\nend\n", file: "s.rb")
      expect(catalog.each.count).to(eq(0))
    end
  end

  describe "default_argument" do
    it "makes an optional positional and keyword parameter required" do
      expect(labels("default_argument"))
        .to(contain_exactly("default => required (name)", "default => required (punct)"))
    end

    it "keeps both defaults with no mutant active" do
      expect(under("default_argument", &:greet)).to(eq("hi world!"))
    end

    it "requires the positional parameter" do
      expect { under("default_argument", "default => required (name)", &:greet) }
        .to(raise_error(ArgumentError, /missing argument: name/))
    end

    it "still accepts the positional argument" do
      expect(under("default_argument", "default => required (name)") { |o| o.greet("bob") }).to(eq("hi bob!"))
    end

    it "requires the keyword parameter" do
      expect { under("default_argument", "default => required (punct)") { |o| o.greet("bob") } }
        .to(raise_error(ArgumentError, /missing keyword: punct/))
    end

    it "still accepts the keyword argument" do
      expect(under("default_argument", "default => required (punct)") { |o| o.greet("bob", punct: "?") })
        .to(eq("hi bob?"))
    end

    # Each mutant's baked `def greet` line, by label.
    def greets
      catalog = built("default_argument")
      overlay = Kimera::Overlay.new(catalog)
      catalog.each.to_h { |m, _p| [m.label, overlay.bake("contracts.rb", contract_src, m.id)[/def greet.*/]] }
    end

    it "bakes to a genuinely required parameter" do
      expect(greets).to(
        eq(
          "default => required (name)" => 'def greet(name, punct: "!")',
          "default => required (punct)" => 'def greet(name = "world", punct:)'
        )
      )
    end

    it "renders a report line for a parameter slice, which is not a parseable expression" do
      m = built("default_argument").each.first.first
      expect(Kimera::Rewrite::Directive.new(m.directive).render("name = \"world\"")).to(eq("name (default removed)"))
    end
  end

  describe "selector_swap filter_map" do
    it "keeps filtering with no mutant active" do
      expect(under("selector_swap") { |o| o.compact([1, nil, 2]) }).to(eq([1, 2]))
    end

    it "stops filtering" do
      expect(under("selector_swap", "filter_map => map") { |o| o.compact([1, nil, 2]) }).to(eq([1, nil, 2]))
    end

    it "is one-way: map is never swapped to filter_map" do
      expect(scan("selector_swap", "def m(xs)\n  xs.map { |x| x }\nend\n", "m.rb").each.count).to(eq(0))
    end
  end

  describe "awkward positions" do
    let(:awkward) { <<~RUBY }
      class Awkward
        def indexes(h, a)
          h[:k] += 1
          h[:a] = h[:b]
          a[0][1]
        end

        def params(a = 1, *rest, k: 2, **opts)
          [a, rest, k, opts]
        end

        def blocks(xs)
          xs.map { |x, y = 2| x.respond_to?(:to_i) ? Integer(x) + y : :skipped }
        end

        def spread(s = <<~TEXT)
          hi
        TEXT
          s
        end
      end
    RUBY

    def safe(catalog) = catalog.points.select(&:safe?).flat_map(&:ids)

    it "hold more than ten schema-safe points" do
      expect(safe(scan(contract_keys, awkward, "awkward.rb")).size).to(be > 10)
    end

    # A point the overlay cannot apply is permanent no_coverage noise.
    it "are all applied by the overlay, into source that parses", :aggregate_failures do
      catalog = scan(contract_keys, awkward, "awkward.rb")
      result = Kimera::Overlay.new(catalog).synthesize("awkward.rb", awkward)
      expect(result.mutant_ids).to(match_array(safe(catalog)))
      expect { RubyVM::AbstractSyntaxTree.parse(result.source) }.not_to(raise_error)
    end
  end

  def parses?(source)
    RubyVM::AbstractSyntaxTree.parse(source)
    true
  rescue SyntaxError
    false
  end

  it "bakes every contract mutant into source that still parses", :aggregate_failures do
    catalog = scan(contract_keys)
    overlay = Kimera::Overlay.new(catalog)
    expect(catalog.each.count).to(be > 5)
    baked = catalog.each.to_h { |mutant, _point| [mutant.label, overlay.bake("contracts.rb", contract_src, mutant.id)] }
    expect(baked.reject { |_label, source| parses?(source) }.keys).to(be_empty)
  end
end
