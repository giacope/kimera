# frozen_string_literal: true

require "kimera/operators"
require "kimera/registry/builder"
require "kimera/runtime"
require "kimera/synthesis/overlay"

# assignment_deletion, nil_literal and keyword_drop: what each one targets,
# what it leaves alone, and that the woven method behaves as the mutant.
RSpec.describe("value operators") do
  def scan(code, *keys)
    Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: keys)).source(code, file: "v.rb")
  end

  def labels(code, *keys) = scan(code, *keys).each.map { |m, _p| m.label }

  def sources(code, *keys) = scan(code, *keys).each.map { |_m, p| p.original_source }

  def live(code, *keys)
    catalog = scan(code, *keys)
    Kimera::Overlay::Source.new(Kimera::Overlay.new(catalog).synthesize("v.rb", code).source).evaluate("v.rb")
    yield(catalog.each.to_h { |m, p| [p.original_source, m.id] })
  ensure
    Kimera::RUNTIME.reset!
    Object.__send__(:remove_const, :ValueOps) if defined?(ValueOps)
  end

  def active(id)
    Kimera::RUNTIME.active = id
    yield
  ensure
    Kimera::RUNTIME.active = nil
  end

  describe "assignment_deletion" do
    let(:code) { <<~RUBY }
      class ValueOps
        attr_reader :name

        def initialize(name)
          @name = name
        end

        def tidy(word)
          word = word.strip
          word
        end

        def total(xs)
          sum = 0
          xs.each { |x| sum = sum + x }
          sum
        end
      end
    RUBY

    it "drops an ivar store and a local that rebinds a bound name, keeping the value", :aggregate_failures do
      expect(sources(code, "assignment_deletion"))
        .to(contain_exactly("@name = name", "word = word.strip", "sum = sum + x"))
      live(code, "assignment_deletion") do |ids|
        expect(ValueOps.new("a").name).to(eq("a"))
        active(ids.fetch("@name = name")) { expect(ValueOps.new("a").name).to(be_nil) }
        active(ids.fetch("word = word.strip")) { expect(ValueOps.new("a").tidy(" b ")).to(eq(" b ")) }
        active(ids.fetch("sum = sum + x")) { expect(ValueOps.new("a").total([1, 2])).to(eq(0)) }
      end
    end

    it "leaves a nil an initializer assigns alone, but not a later reset to nil" do
      code = "class A\n  def initialize\n    @x = nil\n  end\n\n  def clear\n    @x = nil\n  end\nend\n"
      expect(scan(code, "assignment_deletion").each.map { |_m, p| p.method_name }).to(eq(["clear"]))
    end

    it "drops a second write of a name, and reads forwarded parameters", :aggregate_failures do
      code = "def twice(x)\n  y = x\n  y = y + 1\n  y\nend\n\ndef forward(...)\n  z = 1\n  z = z + 1\n  go(...)\nend\n"
      expect(sources(code, "assignment_deletion")).to(eq(["y = y + 1", "z = z + 1"]))
    end

    it "keeps the assigned value as the statement's value" do
      code = "def name=(value)\n  @name = value\nend\n"
      catalog = scan(code, "assignment_deletion")
      mutant, point = catalog.each.first
      expect(Kimera::Rewrite::Directive.render(point.original_source, mutant.directive)).to(eq("value"))
    end

    it "leaves a name's first write, a write inside an expression, and a memo store alone" do
      code = <<~RUBY
        def first(x)
          y = x + 1
          z = (w = y) + 1
          [y, z, w]
        end

        def cached
          return @cached if defined?(@cached)
          @cached = compute
        end

        def block_local(xs)
          xs.each { |x| t = x; t.to_s }
          xs.map { |x| t = x; t }
        end

        def argument(x)
          record(@last = x)
        end
      RUBY
      expect(scan(code, "assignment_deletion").each.count).to(eq(0))
    end
  end

  describe "nil_literal" do
    let(:code) { <<~RUBY }
      class ValueOps
        def find(xs, wanted)
          return nil if xs.empty?
          xs.each { |x| return x if x == wanted }
          nil
        end

        def firsts(xs) = xs.map { |x| next nil if x.empty?; x.first }
      end
    RUBY

    it "makes a returned nil a fresh object", :aggregate_failures do
      expect(labels(code, "nil_literal"))
        .to(contain_exactly("return nil => return Object.new", "nil => Object.new", "next nil => next Object.new"))
      live(code, "nil_literal") do |ids|
        object = ValueOps.new
        expect(object.find([], 1)).to(be_nil)
        active(ids.fetch("return nil")) { expect(object.find([], 1)).to(be_an_instance_of(Object)) }
        active(ids.fetch("nil")) { expect(object.find([2], 1)).to(be_an_instance_of(Object)) }
        active(ids.fetch("next nil")) { expect(object.firsts([[]]).first).to(be_an_instance_of(Object)) }
      end
    end

    it "leaves nil arguments, assignments and comparisons alone" do
      code = "def m(h, x)\n  y = nil\n  h.fetch(x, nil)\n  x == nil\n  return\nend\n"
      expect(scan(code, "nil_literal").each.count).to(eq(0))
    end
  end

  describe "keyword_drop" do
    let(:code) { <<~RUBY }
      class ValueOps
        def pad(word)
          word.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
        end

        def parse(text) = Integer(text, exception: false) { |v| v }
      end
    RUBY

    it "drops one keyword argument at a time", :aggregate_failures do
      expect(labels(code, "keyword_drop"))
        .to(
          contain_exactly(
            "drop keyword `invalid:`", "drop keyword `undef:`", "drop keyword `replace:`", "drop keyword `exception:`"
          )
        )
      live(code, "keyword_drop") do |ids|
        object = ValueOps.new
        expect(object.parse("x")).to(be_nil)
        active(ids.fetch("Integer(text, exception: false) { |v| v }")) do
          expect { object.parse("x") }.to(raise_error(ArgumentError))
        end
      end
    end

    it "leaves a double splat and a computed key alone" do
      code = "def m(opts, k)\n  call(**opts)\n  call(\"\#{k}\": 1)\n  call({ a: 1 })\nend\n"
      expect(scan(code, "keyword_drop").each.count).to(eq(0))
    end
  end
end
