# frozen_string_literal: true

require "kimera/operators"
require "kimera/registry/builder"
require "kimera/runtime"
require "kimera/synthesis/body_trim"
require "kimera/synthesis/overlay"

# super_call, rescue_clause and ensure_clause: what each one targets, what it
# leaves alone, and that the woven method behaves as the mutant when flipped.
RSpec.describe("clause operators") do
  def scan(code, *keys)
    Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: keys)).source(code, file: "c.rb")
  end

  def labels(code, *keys) = scan(code, *keys).each.map { |m, _p| m.label }

  def rendered(code, *keys)
    scan(code, *keys).each.map { |m, p| Kimera::Rewrite::Directive.render(p.original_source, m.directive) }
  end

  def live(code, *keys)
    catalog = scan(code, *keys)
    Kimera::Overlay::Source.new(Kimera::Overlay.new(catalog).synthesize("c.rb", code).source).evaluate("c.rb")
    yield(catalog.each.to_h { |m, _p| [m.label, m.id] })
  ensure
    Kimera::RUNTIME.reset!
  end

  def active(id)
    Kimera::RUNTIME.active = id
    yield
  ensure
    Kimera::RUNTIME.active = nil
  end

  describe "super_call" do
    let(:code) { <<~RUBY }
      class ClauseParent
        def tag(word) = "<\#{word}>"
        def log = (@log ||= [])
        def note(word) = log << word
      end

      class ClauseChild < ClauseParent
        def tag(word)
          super.upcase
        end

        def note(word)
          super(word.strip)
          log.size
        end
      end
    RUBY

    after do
      %i[ClauseChild ClauseParent].each { |name| Object.__send__(:remove_const, name) if Object.const_defined?(name) }
    end

    it "deletes zsuper and super(...) alike, as a statement or a value", :aggregate_failures do
      expect(labels(code, "super_call")).to(contain_exactly("delete `super`", "delete `super(word.strip)`"))
      live(code, "super_call") do |ids|
        child = ClauseChild.new
        expect(child.tag("b")).to(eq("<B>"))
        active(ids.fetch("delete `super`")) { expect { child.tag("b") }.to(raise_error(NoMethodError)) }
        active(ids.fetch("delete `super(word.strip)`")) { expect(ClauseChild.new.note(" x ")).to(eq(0)) }
        expect(ClauseChild.new.note(" x ")).to(eq(1))
      end
    end

    it "leaves the super of respond_to_missing? alone: Object's answers false, as nil does" do
      code = "class A\n  def respond_to_missing?(name, all = false) = name == :x || super\nend\n"
      expect(scan(code, "super_call").each.count).to(eq(0))
    end

    it "takes a super call's block with it" do
      code = "def each(&) = super { |x| yield(x) }\n"
      expect(rendered(code, "super_call")).to(eq(["(statement deleted)"]))
    end
  end

  describe "rescue_clause and ensure_clause" do
    let(:code) { <<~RUBY }
      class ClauseRisky
        attr_reader :closed

        def read(value)
          Integer(value)
        rescue ArgumentError, TypeError => error
          error.class.name
        rescue RangeError
          :range
        else
          :parsed
        ensure
          @closed = true
        end

        def inner(value)
          begin
            Integer(value)
          rescue ArgumentError
            0
          end
        end

        def quiet(value) = (Integer(value) rescue -1)
      end
    RUBY

    after { Object.__send__(:remove_const, :ClauseRisky) if defined?(ClauseRisky) }

    it "drops each rescue clause of a method body, an explicit begin, and a rescue modifier", :aggregate_failures do
      expect(labels(code, "rescue_clause"))
        .to(
          contain_exactly(
            "drop `rescue ArgumentError, TypeError => error`", "drop `rescue RangeError`",
            "drop `rescue ArgumentError`", "drop `rescue` modifier"
          )
        )
      expect(labels(code, "ensure_clause")).to(eq(["drop `ensure`"]))
    end

    it "rescues nothing more once its clause is gone", :aggregate_failures do
      live(code, "rescue_clause") do |ids|
        risky = ClauseRisky.new
        expect(risky.read("x")).to(eq("ArgumentError"))
        active(ids.fetch("drop `rescue ArgumentError, TypeError => error`")) do
          expect { risky.read("x") }.to(raise_error(ArgumentError))
          expect(risky.read("1")).to(eq(:parsed))
        end
        active(ids.fetch("drop `rescue ArgumentError`")) { expect { risky.inner("x") }.to(raise_error(ArgumentError)) }
        active(ids.fetch("drop `rescue` modifier")) { expect { risky.quiet("x") }.to(raise_error(ArgumentError)) }
        expect(risky.quiet("x")).to(eq(-1))
      end
    end

    it "leaves the protected body bare when the last clause goes" do
      code = "def m(v)\n  Integer(v)\nrescue ArgumentError\n  0\nend\n"
      expect(rendered(code, "rescue_clause")).to(eq(["def m(v)\n  Integer(v)\nend"]))
    end

    it "guards a method's own clause inside its body, wrapping only a body that keeps a clause", :aggregate_failures do
      code = "class Plain\n  def m(v)\n    Integer(v)\n  rescue ArgumentError\n    0\n  end\nend\n"
      source = Kimera::Overlay.new(scan(code, "rescue_clause")).synthesize("c.rb", code).source
      guarded = /def m\(v\)\n\s+if ::Kimera::RUNTIME\.active\?\(\d+\)\n\s+Integer\(v\)\n\s+else\n\s+begin\n/
      expect(source).to(match(guarded))
      location = scan(code, "rescue_clause").each.first.last.location
      expect(Kimera::BodyTrim.trimmed(code, [location])).to(include("def m(v)"))
    end

    it "drops the ensure of a method with no body of its own", :aggregate_failures do
      code = "class EmptyEnsure\n  attr_reader :done\n\n  def m\n  ensure\n    @done = true\n  end\nend\n"
      live(code, "ensure_clause") do |ids|
        active(ids.fetch("drop `ensure`")) { expect(EmptyEnsure.new.tap(&:m).done).to(be_nil) }
        expect(EmptyEnsure.new.tap(&:m).done).to(be(true))
      end
    ensure
      Object.__send__(:remove_const, :EmptyEnsure) if defined?(EmptyEnsure)
    end

    it "keeps the else value when the last clause goes" do
      code = "def m(v)\n  Integer(v)\nrescue ArgumentError\n  0\nelse\n  :ok\nend\n"
      expect(rendered(code, "rescue_clause")).to(eq(["def m(v)\n  Integer(v)\n  :ok\nend"]))
    end

    it "skips the cleanup once the ensure is gone", :aggregate_failures do
      live(code, "ensure_clause") do |ids|
        expect(ClauseRisky.new.tap { it.read("1") }.closed).to(be(true))
        active(ids.fetch("drop `ensure`")) { expect(ClauseRisky.new.tap { it.read("1") }.closed).to(be_nil) }
      end
    end

    it "follows a rescue clause to the next under either of Prism's names", :aggregate_failures do
      expect(Kimera::Operators::Clauses.following(Struct.new(:subsequent).new(:next))).to(eq(:next))
      expect(Kimera::Operators::Clauses.following(Struct.new(:consequent).new(:next))).to(eq(:next))
    end

    it "leaves a block's own rescue alone: it has no node to guard" do
      code = "def m(xs)\n  xs.map do |x|\n    Integer(x)\n  rescue ArgumentError\n    0\n  end\nend\n"
      expect(scan(code, "rescue_clause").each.count).to(eq(0))
    end
  end
end
