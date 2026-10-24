# frozen_string_literal: true

require "kimera/operators"
require "kimera/registry/builder"
require "kimera/runtime"
require "kimera/synthesis/body_trim"
require "kimera/synthesis/overlay"
require "property/support/schemata_projection"

RSpec.describe(Kimera::Operators::Visibility) do
  def scan(code)
    Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: ["visibility"])).source(code, file: "vis.rb")
  end

  def names(code) = scan(code).each.map { |_m, p| p.method_name }

  it "targets the public instance methods of a class, module or class << self body" do
    code = <<~RUBY
      class A
        def shown = 1
        def bare; end
        def self.factory = new
        def ==(other) = true
        def to_s = "a"

        protected

        def guarded = 2

        public

        def again = 3
        def named = 4
        def defined_private = 5
        def redefined = 6
        private :named
        private_class_method :factory
        public :again
        private def redefined = 7
        register_hook

        private

        def hidden = 6
        public def lifted = 7
        configure
        def still_hidden = 8

        class << self
          def build = new
        end
      end

      module M
        def helper = 1
        module_function
        def util = 2
      end
    RUBY
    expect(names(code)).to(contain_exactly("shown", "again", "defined_private", "build", "helper"))
  end

  it "is judged warm: its point is schema-safe although it sits in a class body", :aggregate_failures do
    point = scan("class A\n  def shown = 1\nend\n").each.first.last
    expect(point.safe?).to(be(true))
    expect(point.original_source).to(eq("def shown = 1"))
  end

  it "renders the method followed by its private call" do
    mutant, point = scan("class A\n  def shown\n    1\n  end\nend\n").each.first
    expect(Kimera::Rewrite::Directive.new(mutant.directive).render(point.original_source))
      .to(eq("def shown\n    1\n  end\nprivate(:shown)\n"))
  end

  describe "the woven method" do
    let(:code) { <<~RUBY }
      class VisibilityOps
        def total = part + 1
        def part = 1

        def method_missing(name, *args) = name == :part ? :ghost : super
        def respond_to_missing?(name, include_private = false) = name == :part || super
      end
    RUBY
    let(:catalog) { scan(code) }
    let(:ids) { catalog.each.to_h { |m, p| [p.method_name, m.id] } }
    let!(:ledger) { Kimera::RUNTIME.start! }

    before do
      stub_const("VisibilityOps", Class.new)
      Kimera::Overlay::Source.new(Kimera::Overlay.new(catalog).synthesize("vis.rb", code).source).evaluate("vis.rb")
    end

    after do
      Kimera::RUNTIME.stop!(ledger)
    end

    def active(name, &) = Kimera::RUNTIME.during(ids.fetch(name), &)

    it "stays public until its mutant is active" do
      expect([VisibilityOps.new.part, VisibilityOps.public_method_defined?(:part)]).to(eq([1, true]))
    end

    it "turns private while its mutant is active", :aggregate_failures do
      object = VisibilityOps.new
      active("part") do
        expect([object.total, object.part, object.__send__(:part)]).to(eq([2, :ghost, 1]))
        expect(VisibilityOps.private_method_defined?(:part)).to(be(true))
      end
    end

    it "turns public again once its mutant is off" do
      active("part") { VisibilityOps.new.part }
      expect(VisibilityOps.public_method_defined?(:part)).to(be(true))
    end

    # Self-hosted, the outer run's guards write their own ids into every open
    # ledger, so the probe is checked in the source rather than by a call.
    it "records a covering call through a probe that changes nothing" do
      id = ids.fetch("part")
      runtime = "::Kimera::RUNTIME"
      probe = /def part = \(#{runtime}\.active\?\(#{id}\); 1\); #{runtime}\.privatize\(#{id}, self, :part\)$/
      expect(Kimera::Overlay.new(catalog).synthesize("vis.rb", code).source).to(match(probe))
    end
  end

  it "reduces to its bake: the flip to `private`, the probe to nothing" do
    code = "class A\n  def shown\n    1\n  end\n\n  def other(x)\n    x + 1\n  rescue TypeError\n    0\n  end\nend\n"
    schemata = SchemataProjection.check(code, operators: Kimera::Operators.build(keys: %w[visibility rescue_clause]))
    expect(schemata.mismatches).to(be_empty)
  end

  it "keeps a mutated method when the class body is trimmed for a second load" do
    code = "class A\n  def shown = 1\n  def other = 2\nend\n"
    location = scan(code).each.first.last.location
    trimmed = Kimera::BodyTrim.new(code, [location]).trimmed
    expect(trimmed).to(include("def shown = 1"))
  end
end
