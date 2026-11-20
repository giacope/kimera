# frozen_string_literal: true

require "kimera/execution/zygote"

RSpec.describe(Kimera::Runtime) do
  let(:runtime) { described_class.new }

  it "is the one process-wide runtime" do
    expect(Kimera::RUNTIME).to(be_a(described_class))
  end

  describe "in a process that only requires kimera" do
    def fresh(script)
      command = [Gem.ruby, "-I", File.expand_path("../../lib", __dir__), "-e", script]
      output, status = Bundler.with_unbundled_env { Open3.capture2e(*command) }
      expect(status).to(be_success, output)
      output.split
    end

    it "defines no top-level constant but Kimera" do
      expect(fresh('before = Object.constants; require "kimera"; puts(Object.constants - before)')).to(eq(["Kimera"]))
    end

    it "still collects what a forked child reaches" do
      script = <<~RUBY
        require "kimera"
        ledger = Kimera::Runtime::Ledger.new
        Kimera::RUNTIME.during(nil, ledger) { Process.wait(fork { Kimera::RUNTIME.active?(7) }) }
        puts(ledger.drain!)
      RUBY
      expect(fresh(script)).to(eq(["7"]))
    end
  end

  it "keeps the runtime a second copy of this file finds already bound" do
    bound = Kimera::RUNTIME
    Kimera::Warnings.silenced.during { load(described_class::SOURCE_PATH) }
    expect(Kimera::RUNTIME).to(equal(bound))
  end

  def spilled(ledger) = Dir.glob(File.join(Dir.tmpdir, "kimera-ledger-#{Process.pid}-#{ledger.object_id}-*"))

  def pushes(&)
    count = 0
    TracePoint.new(:call) { |call| count += 1 if call.method_id == :push }.enable(&)
    count
  end

  def asked(shared, *ids)
    Warning[:experimental] = false
    ractor = Ractor.new(shared, ids) { |runtime, mutants| mutants.map { runtime.active?(it) }.last }
    ractor.respond_to?(:value) ? ractor.value : ractor.take
  end

  describe "inside a non-main Ractor" do
    def remote(shared, *ids)
      child = fork { exit!(asked(shared, *ids) ? 0 : 7) }
      { 0 => true, 7 => false }.fetch(Process.wait2(child).last.exitstatus)
    end

    it "is shareable, and answers which mutant is active", :aggregate_failures do
      runtime.active = 4
      expect(Ractor.shareable?(runtime)).to(be(true))
      expect(remote(runtime, 4)).to(be(true))
      expect(remote(runtime, 5)).to(be(false))
    end

    it "records what it reaches in the main Ractor's open ledger, once per id", :aggregate_failures do
      ledger = runtime.start!
      runtime.active = 4
      expect([remote(runtime, 4), remote(runtime, 9)]).to(eq([true, false]))
      expect(runtime.stop!(ledger)).to(contain_exactly(4, 9))
      expect(remote(runtime, 4)).to(be(true))
    end

    it "writes an id it reaches twice to the open ledger's spill once" do
      ledger = runtime.start!
      remote(runtime, 4, 4)
      expect(spilled(ledger).map { File.read(it) }).to(eq(["4\n"]))
    ensure
      runtime.stop!(ledger)
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

    it "asks nothing of its sink while no ledger is open, before the first one and after the last" do
      fresh = pushes { runtime.active?(1) }
      runtime.stop!(runtime.start!)
      expect([fresh, pushes { runtime.active?(1) }]).to(eq([0, 0]))
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
      expect(ledger.drain!).to(eq([7]))
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

    it "tolerates closing a ledger when no coverage pass is active" do
      ledger = runtime.start!
      runtime.stop!(ledger)
      expect { runtime.stop!(ledger) }.not_to(raise_error)
    end

    it "leaves no ledger open once the last one closes" do
      ledger = runtime.start!
      runtime.stop!(ledger)
      expect(runtime.ledgers).to(be_empty)
    end

    def left(opened) = runtime.ledgers.map { |ledger| opened.index(ledger) }

    def stacked
      opened = Array.new(3) { runtime.start! }
      runtime.active?(7)
      middle = runtime.stop!(opened[1])
      runtime.active?(8)
      [middle, opened.map(&:drain!), left(opened)]
    ensure
      opened.each { |ledger| runtime.stop!(ledger) }
    end

    it "records on each of three open ledgers, and on the two left when the middle one closes" do
      expect(stacked).to(eq([[7], [[7, 8], [], [7, 8]], [0, 2]]))
    end

    it "records straight on the one open ledger, and on nothing once it closes", :aggregate_failures do
      ledger = runtime.start!
      expect(pushes { runtime.active?(1) }).to(eq(1))
      runtime.stop!(ledger)
      expect(runtime.ledgers).to(be_empty)
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
      [ledger.drain!, spilled(ledger)]
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
      expect(spill).to(be_empty)
    end

    it "reach it from a grandchild too" do
      touched, = forked(&grandchild(42))
      expect(touched).to(include(42))
    end

    def ractor(mutant) = -> { asked(Kimera::RUNTIME, mutant).then { exit!(0) } }

    it "reach it from a Ractor the child starts" do
      touched, = forked(&ractor(43))
      expect(touched).to(include(43))
    end

    it "leave the parent recording on its own ledger" do
      ledger = Kimera::RUNTIME.start!
      Process.wait(fork(&child(44)))
      expect(Kimera::RUNTIME.ledgers.count { it.equal?(ledger) }).to(eq(1))
    ensure
      Kimera::RUNTIME.stop!(ledger)
    end

    it "are not looked for while no ledger is open" do
      expect(runtime.leaks).to(be_empty)
    end

    it "write each mutant once" do
      Dir.mktmpdir do |dir|
        spill = described_class::Spill.new(File.join(dir, "spill"), {})
        [3, 3, 4].each { spill.push(it) }
        expect(File.read(File.join(dir, "spill"))).to(eq("3\n4\n"))
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
      owner.class_eval { public(:shown) }
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

    def forks(holders)
      Kimera::RUNTIME.privatize(990_001, mixin, :sized)
      walks { yield(Array.new(5) { Kimera::Execution::Zygote.new.call { switched(holders) } }) }
    end

    it "walks once for the flips registered before many forks, and never in a child" do
      holders = [Class.new.include(mixin).tap { it.alias_method(:size, :sized) }]
      children = nil
      parent = Kimera::RUNTIME.contained { forks(holders) { children = it } }
      expect([parent, children.uniq]).to(eq([1, [[0, [false]]]]))
    end

    it "leaves an includer's own method of that name alone" do
      box = Class.new.include(mixin).tap { it.define_method(:sized) { 4 } }
      runtime.privatize(7, mixin, :sized)
      runtime.active = 7
      expect(box.public_method_defined?(:sized)).to(be(true))
    end

    def outsiders
      stranger = Class.new.tap { it.define_method(:copy, mixin.instance_method(:sized)) }
      [stranger, Class.new(stranger).include(mixin)]
    end

    it "leaves the copy a class outside its family defined from it public, there and in an includer below it" do
      holders = outsiders
      runtime.privatize(7, mixin, :sized)
      runtime.active = 7
      expect(visible(holders, :copy)).to(eq([true, true]))
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

    def cleared
      count = 0
      controller = Class.new(owner).tap { it.define_singleton_method(:clear_action_methods!) { count += 1 } }
      runtime.privatize(5, controller, :shown)
      runtime.active = 5
      runtime.active = nil
      count
    end

    it "clears a Rails controller's cached actions with each flip" do
      expect(cleared).to(eq(2))
    end
  end
end
