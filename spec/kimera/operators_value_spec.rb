# frozen_string_literal: true

require "kimera/operators"
require "kimera/registry/builder"
require "kimera/runtime"
require "kimera/synthesis/overlay"

# assignment_deletion, nil_literal and keyword_drop: what each one targets,
# what it leaves alone, and that the woven method behaves as the mutant.
RSpec.describe(Kimera::Operators) do
  def scan(code, *keys)
    Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: keys)).source(code, file: "v.rb")
  end

  def labels(code, *keys) = scan(code, *keys).each.map { |m, _p| m.label }

  def sources(code, *keys) = scan(code, *keys).each.map { |_m, p| p.original_source }

  def live(code, *keys)
    stub_const("ValueOps", Class.new)
    catalog = scan(code, *keys)
    Kimera::Overlay::Source.new(Kimera::Overlay.new(catalog).synthesize("v.rb", code).source).evaluate("v.rb")
    yield(catalog.each.to_h { |m, p| [p.original_source, m.id] })
  end

  def active(id, &) = Kimera::RUNTIME.during(id, &)

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

    it "drops an ivar store and a local that rebinds a bound name" do
      expect(sources(code, "assignment_deletion"))
        .to(contain_exactly("@name = name", "word = word.strip", "sum = sum + x"))
    end

    it "keeps the value with no mutant active, and loses each store under its own" do
      live(code, "assignment_deletion") do |ids|
        answers = [
          ValueOps.new("a").name, active(ids.fetch("@name = name")) { ValueOps.new("a").name },
          active(ids.fetch("word = word.strip")) { ValueOps.new("a").tidy(" b ") },
          active(ids.fetch("sum = sum + x")) { ValueOps.new("a").total([1, 2]) }
        ]
        expect(answers).to(eq(["a", nil, " b ", 0]))
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
      expect(Kimera::Rewrite::Directive.new(mutant.directive).render(point.original_source)).to(eq("value"))
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

        def defaulted(x = helper)
          helper = x + 1
          helper
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

    it "makes a returned nil a fresh object" do
      expect(labels(code, "nil_literal"))
        .to(contain_exactly("return nil => return Object.new", "nil => Object.new", "next nil => next Object.new"))
    end

    it "answers nil with no mutant active, and a fresh object under each" do
      live(code, "nil_literal") do |ids|
        object = ValueOps.new
        answers = [
          object.find([], 1), active(ids.fetch("return nil")) { object.find([], 1) },
          active(ids.fetch("nil")) { object.find([2], 1) }, active(ids.fetch("next nil")) { object.firsts([[]]).first }
        ]
        expect(answers).to(match([be_nil, *Array.new(3) { be_an_instance_of(Object) }]))
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

    it "drops one keyword argument at a time" do
      expect(labels(code, "keyword_drop"))
        .to(
          contain_exactly(
            "drop keyword `invalid:`", "drop keyword `undef:`", "drop keyword `replace:`", "drop keyword `exception:`"
          )
        )
    end

    it "raises where the dropped keyword let the call answer nil", :aggregate_failures do
      live(code, "keyword_drop") do |ids|
        object = ValueOps.new
        expect(object.parse("x")).to(be_nil)
        expect { active(ids.fetch("Integer(text, exception: false) { |v| v }")) { object.parse("x") } }
          .to(raise_error(ArgumentError))
      end
    end

    it "leaves a double splat and a computed key alone" do
      code = "def m(opts, k)\n  call(**opts)\n  call(\"\#{k}\": 1)\n  call({ a: 1 })\nend\n"
      expect(scan(code, "keyword_drop").each.count).to(eq(0))
    end
  end
end
