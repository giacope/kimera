# frozen_string_literal: true

require "kimera/execution/zygote"

RSpec.describe(Kimera::Runtime) do
  let(:runtime) { described_class.new }

  it "is the one process-wide runtime, and the only constant kimera defines outside its namespace is Kimera" do
    expect(Kimera::RUNTIME).to(be_a(described_class))
  end

  it "keeps the runtime a second copy of this file finds already bound" do
    bound = Kimera::RUNTIME
    Kimera::Warnings.silenced.during { load(described_class::SOURCE_PATH) }
    expect(Kimera::RUNTIME).to(equal(bound))
  end

  describe "inside a non-main Ractor" do
    def in_ractor(shared, id)
      experimental = Warning[:experimental]
      Warning[:experimental] = false
      ractor = Ractor.new(shared, id) { |runtime, asked| runtime.active?(asked) }
      ractor.respond_to?(:value) ? ractor.value : ractor.take
    ensure
      Warning[:experimental] = experimental
    end

    it "is shareable, and answers which mutant is active", :aggregate_failures do
      runtime.active = 4
      expect(Ractor.shareable?(runtime)).to(be(true))
      expect(in_ractor(runtime, 4)).to(be(true))
      expect(in_ractor(runtime, 5)).to(be(false))
    end

    it "records what it reaches in the main Ractor's open ledger, once per id", :aggregate_failures do
      ledger = runtime.start!
      runtime.active = 4
      expect([in_ractor(runtime, 4), in_ractor(runtime, 9)]).to(eq([true, false]))
      expect(runtime.stop!(ledger)).to(contain_exactly(4, 9))
      expect(in_ractor(runtime, 4)).to(be(true))
    end
  end

  describe "#active / #active?" do
    it "selects the original when active is nil", :aggregate_failures do
      runtime.active = nil
      expect(runtime.active?(1)).to(be(false))
      expect(runtime.active?(2)).to(be(false))
    end

    it "selects exactly one mutant", :aggregate_failures do
      runtime.active = 2
      expect(runtime.active?(1)).to(be(false))
      expect(runtime.active?(2)).to(be(true))
    end

    it "coerces the active id to an Integer", :aggregate_failures do
      runtime.active = "7"
      expect(runtime.active).to(eq(7))
      expect(runtime.active?(7)).to(be(true))
    end
  end

  describe "#reset!" do
    it "deselects the active mutant", :aggregate_failures do
      runtime.active = 5
      runtime.reset!
      expect(runtime.active).to(be_nil)
      expect(runtime.active?(5)).to(be(false))
    end
  end

  describe "#during" do
    it "selects the mutant only while its block runs, then the one selected before" do
      runtime.active = 5
      inside = runtime.during(9) { runtime.active }
      expect([inside, runtime.active]).to(eq([9, 5]))
    end

    it "hands the switch back when its block raises", :aggregate_failures do
      runtime.active = 5
      expect { runtime.during(9) { raise(KeyError) } }.to(raise_error(KeyError))
      expect(runtime.active).to(eq(5))
    end

    it "answers its block's value" do
      expect(runtime.during(nil) { :answer }).to(eq(:answer))
    end
  end

  describe "coverage touch-ledgers" do
    def touches
      ledger = runtime.start!
      [10, 11, 10].each { |mutant| runtime.active?(mutant) }
      [ledger.drain!, ledger.drain!]
    ensure
      runtime.stop!(ledger)
    end

    it "records touches on an open ledger and drains them uniquely", :aggregate_failures do
      touches = self.touches
      expect(touches.first).to(contain_exactly(10, 11))
      expect(touches.last).to(eq([]))
    end

    it "stops recording on a ledger once it is closed" do
      ledger = runtime.start!
      runtime.stop!(ledger)
      runtime.active?(5)
      expect(ledger.drain!).to(be_empty)
    end

    it "keeps one entry per mutant however often its guard runs" do
      ledger = runtime.start!
      100_000.times { runtime.active?(7) }
      expect(ledger.__send__(:ids).size).to(eq(1))
    ensure
      runtime.stop!(ledger)
    end

    def close(ledger, mutant)
      runtime.stop!(ledger)
      runtime.active?(mutant)
      ledger
    end

    def nested
      outer, inner = Array.new(2) { runtime.start! }
      runtime.active?(7)
      drain = inner.drain!

      close(inner, 8)
      [drain, outer.drain!]
    ensure
      [outer, inner].each { |ledger| runtime.stop!(ledger) }
    end

    it "records on every open ledger, so nested measurers cannot steal touches", :aggregate_failures do
      drains = nested
      expect(drains.first).to(eq([7]))
      expect(drains.last).to(contain_exactly(7, 8))
    end

    def drain(mutant, ledger)
      runtime.active?(mutant)
      ledger.drain!
    end

    def fresh
      ledger = runtime.start!
      ledger.drain!
      ledger
    end

    def isolation
      outer = runtime.start!
      drain(1, outer)
      close(fresh, 2)
      outer.drain!
    ensure
      runtime.stop!(outer)
    end

    it "closes only the given ledger, even when both are drained to empty" do
      expect(isolation).to(eq([2]))
    end

    def preserve
      saved = runtime.instance_variable_get(:@ledgers)
      runtime.instance_variable_set(:@ledgers, Kimera::Runtime::NONE)
      yield
    ensure
      runtime.instance_variable_set(:@ledgers, saved)
    end

    it "tolerates closing a ledger when no coverage pass is active" do
      preserve do
        ledger = runtime.start!
        runtime.stop!(ledger)
        expect { runtime.stop!(ledger) }.not_to(raise_error)
      end
    end

    it "leaves no ledger open once the last one closes" do
      preserve do
        ledger = runtime.start!
        runtime.stop!(ledger)
        expect(runtime.leaks).to(be_empty)
      end
    end

    def reset
      ledger = runtime.start!
      runtime.active?(3)
      runtime.reset!
      runtime.active?(4)
      ledger.drain!
    ensure
      runtime.stop!(ledger)
    end

    it "keeps open ledgers (and their contents) across reset!" do
      expect(reset).to(contain_exactly(3, 4))
    end
  end

  describe "touches made in a forked child" do
    def forked(&)
      ledger = Kimera::RUNTIME.start!
      Process.wait(fork(&))
      [ledger.drain!, ledger.__send__(:spill)]
    ensure
      Kimera::RUNTIME.stop!(ledger)
    end

    def child(mutant)
      lambda do
        Kimera::RUNTIME.active?(mutant)
        exit!(0)
      end
    end

    def grandchild(mutant)
      lambda do
        Process.wait(fork(&child(mutant)))
        exit!(0)
      end
    end

    it "reach the parent's ledger, and leave no spill file behind", :aggregate_failures do
      touched, spill = forked(&child(41))
      expect(touched).to(include(41))
      expect(File.exist?(spill)).to(be(false))
    end

    it "reach it from a grandchild too" do
      touched, = forked(&grandchild(42))
      expect(touched).to(include(42))
    end

    it "are not looked for while no ledger is open" do
      expect(runtime.leaks).to(be_empty)
    end

    it "write each mutant once" do
      Dir.mktmpdir do |dir|
        spill = described_class::Spill.new(File.join(dir, "spill"), {})
        [3, 3, 4].each { spill.push(it) }
        expect(File.read(spill.__send__(:leak))).to(eq("3\n4\n"))
      end
    end
  end

  describe "#privatize" do
    let(:owner) { Class.new { def shown = 1 } }

    def privacy(ids)
      ids.map do |id|
        runtime.active = id
        owner.private_method_defined?(:shown)
      end
    end

    it "flips a registered method on activation and back on deactivation", :aggregate_failures do
      runtime.privatize(3, owner, :shown)
      expect(privacy([3, 4, 3])).to(eq([true, false, true]))
      runtime.reset!
      expect(owner.public_method_defined?(:shown)).to(be(true))
    end

    def overridden
      runtime.privatize(6, owner, :shown)
      owner.class_eval do
        alias_method :before, :shown
        def shown = before + 1
      end
    end

    it "flips the names that hold the registered definition, not a later redefinition", :aggregate_failures do
      overridden
      runtime.active = 6
      expect([owner.private_method_defined?(:before), owner.public_method_defined?(:shown)]).to(eq([true, true]))
      runtime.active = nil
      expect(owner.public_method_defined?(:before)).to(be(true))
    end

    def mixin = @_mixin ||= Module.new { def sized = 3 }

    def visible(holders, name) = holders.map { it.public_method_defined?(name) }

    def aliased
      box = Class.new.include(mixin).tap { it.alias_method(:size, :sized) }
      single = Object.new.extend(mixin).singleton_class.tap { it.alias_method(:size, :sized) }
      runtime.privatize(7, mixin, :sized)
      [box, single]
    end

    it "flips the aliases an includer or an extended object took of it", :aggregate_failures do
      holders = aliased
      runtime.active = 7
      expect(visible(holders, :size)).to(eq([false, false]))
      runtime.active = nil
      expect(visible(holders, :size)).to(eq([true, true]))
    end

    it "leaves the flips of the active mutant as they are when it is switched on again" do
      runtime.privatize(3, owner, :shown)
      runtime.active = 3
      owner.__send__(:public, :shown)
      runtime.active = 3
      expect(owner.public_method_defined?(:shown)).to(be(true))
    end

    it "finds the holders of a flip no fork has surveyed on its first switch, and keeps them" do
      holders = aliased
      walked = walks { [7, nil, 7].each { runtime.active = it } }
      expect([walked, visible(holders, :size)]).to(eq([1, [false, false]]))
    end

    def switched(holders)
      hidden = nil
      [walks { hidden = Kimera::RUNTIME.during(990_001) { visible(holders, :size) } }, hidden]
    end

    it "walks once for the flips registered before many forks, and never in a child" do
      holders = [Class.new.include(mixin).tap { it.alias_method(:size, :sized) }]
      Kimera::RUNTIME.privatize(990_001, mixin, :sized)
      children = nil
      parent = walks { children = Array.new(5) { Kimera::Execution::Zygote.new.call { switched(holders) } } }
      expect([parent, children.uniq]).to(eq([1, [[0, [false]]]]))
    end

    it "leaves an includer's own method of that name alone" do
      box = Class.new.include(mixin).tap { it.define_method(:sized) { 4 } }
      runtime.privatize(7, mixin, :sized)
      runtime.active = 7
      expect(box.public_method_defined?(:sized)).to(be(true))
    end

    it "flips a method registered while its mutant is active, and every one of them back", :aggregate_failures do
      holders = [Class.new { def shown = 1 }, owner].each { runtime.privatize(9, it, :shown) if (runtime.active = 9) }
      expect(visible(holders, :shown)).to(eq([false, false]))
      runtime.active = nil
      expect(visible(holders, :shown)).to(eq([true, true]))
    end

    it "leaves a method registered under another active mutant public" do
      runtime.active = 4
      runtime.privatize(9, owner, :shown)
      expect(owner.public_method_defined?(:shown)).to(be(true))
    end

    it "clears a Rails controller's cached actions with each flip" do
      controller = Class.new(owner) { def self.clear_action_methods! = (@cleared = (@cleared || 0) + 1) }
      runtime.privatize(5, controller, :shown)
      runtime.active = 5
      runtime.active = nil
      expect(controller.instance_variable_get(:@cleared)).to(eq(2))
    end
  end
end
