# frozen_string_literal: true

require "kimera/operators"
require "kimera/registry/builder"
require "kimera/runtime"
require "kimera/synthesis/overlay"

# Each family is checked in the registry, a live overlay, and baked source.
# default_argument bakes and overlays by different mechanisms.
RSpec.describe("contract operators") do
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

  def built(key)
    Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: [key])).source(contract_src, file: "contracts.rb")
  end

  def labels(key)
    built(key).each.map { |m, _p| m.label }
  end

  def with_overlay(key)
    catalog = built(key)
    Kimera::Overlay::Source.new(Kimera::Overlay.new(catalog).synthesize("contracts.rb", contract_src).source)
      .evaluate(File.expand_path("contracts.rb"))
    yield(catalog.each.to_h { |m, _p| [m.label, m.id] }, catalog)
  ensure
    Kimera::RUNTIME.reset!
    Object.__send__(:remove_const, :Contracts) if defined?(Contracts)
  end

  def active(id)
    Kimera::RUNTIME.active = id
    yield
  ensure
    Kimera::RUNTIME.active = nil
  end

  describe "index_fetch" do
    it "turns a tolerated miss into a KeyError", :aggregate_failures do
      expect(labels("index_fetch")).to(eq(["[] => fetch"]))
      with_overlay("index_fetch") do |ids|
        object = Contracts.new
        expect(object.lookup({ a: 1 }, :a)).to(eq(1))
        expect(object.lookup({ a: 1 }, :nope)).to(be_nil)
        active(ids.fetch("[] => fetch")) do
          expect(object.lookup({ a: 1 }, :a)).to(eq(1))
          expect { object.lookup({ a: 1 }, :nope) }.to(raise_error(KeyError))
        end
      end
    end

    it "carries the bare directive and skips writes, multi-index reads and splats", :aggregate_failures do
      m = built("index_fetch").each.first.first
      expect(m.directive).to(eq("type" => "index_to_fetch"))

      src = <<~RUBY
        def m(h, a, keys)
          h[:k] = 1
          a[1, 2]
          h[*keys]
          h[:k]
        end
      RUBY
      catalog = Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: ["index_fetch"]))
        .source(src, file: "i.rb")
      expect(catalog.each.map { |_mutant, point| point.original_source }).to(eq(["h[:k]"]))
    end

    it "rejects a block form, which is not a plain read" do
      blocked = Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: ["index_fetch"]))
        .source("def m(h, k)\n  h[k] { |x| x }\nend\n", file: "i.rb")
      expect(blocked.each.count).to(eq(0))
    end

    # Dropping `&.` too would mutate nil- and miss-tolerance at once, so a survivor is unattributable.
    it "rewrites the explicit and safe-navigated spellings, preserving &.", :aggregate_failures do
      src = <<~RUBY
        class Spellings
          def explicit(h, k)
            h.[](k)
          end

          def maybe(h, k)
            h&.[](k)
          end
        end
      RUBY
      catalog = Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: ["index_fetch"]))
        .source(src, file: "spellings.rb")
      sources = catalog.each.map { |m, p| Kimera::Rewrite::Directive.render(p.original_source, m.directive) }
      expect(sources).to(contain_exactly("h.fetch(k)", "h&.fetch(k)"))

      result = Kimera::Overlay.new(catalog).synthesize("spellings.rb", src)
      Kimera::Overlay::Source.new(result.source).evaluate(File.expand_path("spellings.rb"))
      ids = catalog.each.to_h { |m, p| [p.original_source, m.id] }
      object = Spellings.new
      expect(object.explicit({ a: 1 }, :nope)).to(be_nil)
      expect(object.maybe(nil, :k)).to(be_nil)
      active(ids.fetch("h.[](k)")) { expect { object.explicit({ a: 1 }, :nope) }.to(raise_error(KeyError)) }
      active(ids.fetch("h&.[](k)")) do
        expect(object.maybe(nil, :k)).to(be_nil)
        expect { object.maybe({ a: 1 }, :nope) }.to(raise_error(KeyError))
      end
    ensure
      Kimera::RUNTIME.reset!
      Object.__send__(:remove_const, :Spellings) if defined?(Spellings)
    end
  end

  describe "kernel_coercion" do
    it "drops the normalization, exposing what the argument really is", :aggregate_failures do
      expect(labels("kernel_coercion")).to(eq(["delete Array()"]))
      with_overlay("kernel_coercion") do |ids|
        object = Contracts.new
        expect(object.norm(nil)).to(eq([]))
        active(ids.fetch("delete Array()")) { expect(object.norm(nil)).to(be_nil) }
      end
    end

    it "skips a receiver'd call, a block, and multi-argument Integer()" do
      src = <<~RUBY
        def m(x, s)
          Foo.Array(x)
          Integer(s, 16)
          Array(x) { |e| e }
          String(x)
        end
      RUBY
      catalog = Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: ["kernel_coercion"]))
        .source(src, file: "k.rb")
      expect(catalog.each.map { |m, _p| m.label }).to(eq(["delete String()"]))
    end

    # `Array(*xs)` does not unwrap to a single value.
    it "rejects a splatted argument" do
      catalog = Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: ["kernel_coercion"]))
        .source("def m(xs)\n  Array(*xs)\nend\n", file: "k.rb")
      expect(catalog.each.count).to(eq(0))
    end
  end

  describe "respond_to_guard" do
    it "collapses the duck-type check to the receiver's own truthiness", :aggregate_failures do
      expect(labels("respond_to_guard")).to(eq(["delete .respond_to?"]))
      with_overlay("respond_to_guard") do |ids|
        object = Contracts.new
        expect(object.duck([1])).to(be(true))
        expect(object.duck(1)).to(be(false))
        active(ids.fetch("delete .respond_to?")) { expect(object.duck(1)).to(eq(1)) }
      end
    end

    it "accepts the private-methods arity but not a computed method name" do
      src = <<~RUBY
        def m(x, name)
          x.respond_to?(:size, true)
          x.respond_to?(name)
        end
      RUBY
      catalog = Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: ["respond_to_guard"]))
        .source(src, file: "r.rb")
      expect(catalog.each.map { |_m, p| p.original_source }).to(eq(["x.respond_to?(:size, true)"]))
    end

    it "matches only a receiver'd, blockless respond_to? of arity 1..2" do
      {
        "another selector" => "def m(x)\n  x.respond_to_missing?(:a)\nend\n",
        "receiverless" => "def m\n  respond_to?(:a)\nend\n",
        "block form" => "def m(x)\n  x.respond_to?(:a) { |y| y }\nend\n",
        "over-arity" => "def m(x)\n  x.respond_to?(:a, true, 1)\nend\n"
      }.each do |name, src|
        catalog = Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: ["respond_to_guard"]))
          .source(src, file: "r.rb")
        expect(catalog.each.count).to(eq(0), "#{name} should not match")
      end
    end
  end

  describe "symbol_literal" do
    it "renames a symbol so any name-identity dependency breaks", :aggregate_failures do
      with_overlay("symbol_literal") do |ids|
        object = Contracts.new
        expect(object.tag).to(eq(:ok))
        active(ids.fetch(":ok => :ok__kimera__")) { expect(object.tag).to(eq(:ok__kimera__)) }
      end
    end

    # A label (`tier:`) has no parser-side node, so it would report no_coverage forever.
    it "skips label position but keeps every expression spelling", :aggregate_failures do
      src = <<~RUBY
        def m(o)
          o.f(tier: 1)
          {gold: 1, :silver => 2, "bronze": 3}
          %i[copper]
          o.send(:tin)
        end
      RUBY
      catalog = Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: ["symbol_literal"]))
        .source(src, file: "s.rb")
      expect(catalog.each.map { |_m, p| p.original_source }).to(contain_exactly(":silver", "copper", ":tin"))

      result = Kimera::Overlay.new(catalog).synthesize("s.rb", src)
      expect(result.mutant_ids.size).to(eq(catalog.each.count))
    end

    it "carries the renamed value and leaves an empty symbol alone", :aggregate_failures do
      m = built("symbol_literal").each.find { |mu, _p| mu.label.start_with?(":ok") }.first
      expect(m.directive).to(eq("type" => "symbol_literal", "value" => "ok__kimera__"))

      catalog = Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: ["symbol_literal"]))
        .source("def m\n  :\"\"\nend\n", file: "s.rb")
      expect(catalog.each.count).to(eq(0))
    end
  end

  describe "default_argument" do
    it "makes an optional positional and keyword parameter required", :aggregate_failures do
      expect(labels("default_argument"))
        .to(contain_exactly("default => required (name)", "default => required (punct)"))

      with_overlay("default_argument") do |ids|
        object = Contracts.new
        expect(object.greet).to(eq("hi world!"))

        active(ids.fetch("default => required (name)")) do
          expect { object.greet }.to(raise_error(ArgumentError, /missing argument: name/))
          expect(object.greet("bob")).to(eq("hi bob!"))
        end

        active(ids.fetch("default => required (punct)")) do
          expect { object.greet("bob") }.to(raise_error(ArgumentError, /missing keyword: punct/))
          expect(object.greet("bob", punct: "?")).to(eq("hi bob?"))
        end
      end
    end

    it "bakes to a genuinely required parameter", :aggregate_failures do
      catalog = built("default_argument")
      overlay = Kimera::Overlay.new(catalog)
      baked =
        catalog.each.to_h do |m, _p|
          [m.label, overlay.bake("contracts.rb", contract_src, m.id).lines.grep(/def greet/).first.strip]
        end
      expect(baked.fetch("default => required (name)")).to(eq('def greet(name, punct: "!")'))
      expect(baked.fetch("default => required (punct)")).to(eq('def greet(name = "world", punct:)'))
    end

    it "renders a report line for a parameter slice, which is not a parseable expression" do
      m = built("default_argument").each.first.first
      expect(Kimera::Rewrite::Directive.render("name = \"world\"", m.directive)).to(eq("name (default removed)"))
    end
  end

  describe "selector_swap filter_map" do
    it "stops filtering, one-way (map is never swapped to filter_map)", :aggregate_failures do
      with_overlay("selector_swap") do |ids|
        object = Contracts.new
        expect(object.compact([1, nil, 2])).to(eq([1, 2]))
        active(ids.fetch("filter_map => map")) { expect(object.compact([1, nil, 2])).to(eq([1, nil, 2])) }
      end

      catalog = Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: ["selector_swap"]))
        .source("def m(xs)\n  xs.map { |x| x }\nend\n", file: "m.rb")
      expect(catalog.each.count).to(eq(0))
    end
  end

  # A point the overlay cannot apply is permanent no_coverage noise.
  it "applies every schema-safe point it proposes, across awkward positions", :aggregate_failures do
    keys = %w[index_fetch kernel_coercion respond_to_guard symbol_literal default_argument]
    src = <<~RUBY
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
    catalog = Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: keys)).source(src, file: "awkward.rb")
    safe = catalog.points.select(&:safe?).flat_map(&:ids)
    expect(safe.size).to(be > 10)

    result = Kimera::Overlay.new(catalog).synthesize("awkward.rb", src)
    expect(result.mutant_ids).to(match_array(safe))
    expect { RubyVM::AbstractSyntaxTree.parse(result.source) }.not_to(raise_error)
  end

  it "bakes every contract mutant into source that still parses", :aggregate_failures do
    keys = %w[index_fetch kernel_coercion respond_to_guard symbol_literal default_argument]
    catalog = Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: keys))
      .source(contract_src, file: "contracts.rb")
    overlay = Kimera::Overlay.new(catalog)
    expect(catalog.each.count).to(be > 5)
    catalog.each.map { |mutant, _point| mutant }.each do |mutant|
      baked = overlay.bake("contracts.rb", contract_src, mutant.id)
      message = "#{mutant.label} baked to unparseable source"
      expect { RubyVM::AbstractSyntaxTree.parse(baked) }.not_to(raise_error, message)
    end
  end
end
