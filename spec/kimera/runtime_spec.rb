# frozen_string_literal: true

RSpec.describe(Kimera::Runtime) do
  let(:runtime) { described_class.new }

  it "is the one process-wide runtime, and the only constant kimera defines outside its namespace is Kimera" do
    expect(Kimera::RUNTIME).to(be_a(described_class))
  end

  it "keeps the runtime a second copy of this file finds already bound" do
    bound = Kimera::RUNTIME
    Kimera::Warnings::SILENCED.during { load(described_class::SOURCE_PATH) }
    expect(Kimera::RUNTIME).to(equal(bound))
  end

  # R3K3: a mutated method called inside a Ractor raised Ractor::IsolationError.
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
      expect(in_ractor(runtime, 4)).to(be(true))
      expect(in_ractor(runtime, 9)).to(be(false))
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

  describe "#overlay" do
    it "is overlaying only while its block runs" do
      inside = runtime.overlay { runtime.overlaying? }
      expect([runtime.overlaying?, inside, runtime.overlaying?]).to(eq([false, true, false]))
    end
  end

  # Assert only through our own handles: when self-hosted, an outer harness
  # holds a ledger open for the whole run.
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
      expect(touches.last).to(eq([])) # draining clears the ledger
    end

    it "stops recording on a ledger once it is closed" do
      ledger = runtime.start!
      runtime.stop!(ledger)
      runtime.active?(5)
      expect(ledger.drain!).to(be_empty)
    end

    # A guard in a hot loop runs millions of times; the ledger holds each id once.
    it "keeps one entry per mutant however often its guard runs" do
      ledger = runtime.start!
      100_000.times { runtime.active?(7) }
      expect(ledger.ids.size).to(eq(1))
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
      # Drain before close stops the ledger.
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

    # Drained ledgers are equal empty arrays, so Array#delete would evict the
    # outer one too. Self-hosted, that zeroed coverage for later examples.
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
      drain(1, outer) # outer now == []
      close(fresh, 2) # inner also == []; must keep the empty outer
      outer.drain!
    ensure
      runtime.stop!(outer)
    end

    it "closes only the given ledger, even when both are drained to empty" do
      expect(isolation).to(eq([2]))
    end

    # Start from an empty table: an outer measurer or leaked ledgers would
    # skip the empty-table path.
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

    # Self-hosted suites call reset! in hooks; the harness's touches must survive.
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

  # Asserted through our own ledger: a self-hosting harness may hold its own
  # open too, and the child writes to both.
  describe "touches made in a forked child" do
    def forked(&)
      ledger = Kimera::RUNTIME.start!
      Process.wait(fork(&))
      [ledger.drain!, ledger.spill]
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
        expect(File.read(spill.leak)).to(eq("3\n4\n"))
      end
    end
  end

  describe "#privatize" do
    let(:owner) { Class.new { def shown = 1 } }

    it "flips a registered method on activation and back on deactivation", :aggregate_failures do
      runtime.privatize(3, owner, :shown)
      runtime.active = 3
      expect(owner.private_method_defined?(:shown)).to(be(true))
      runtime.active = 4
      expect(owner.public_method_defined?(:shown)).to(be(true))
      runtime.active = 3
      runtime.reset!
      expect(owner.public_method_defined?(:shown)).to(be(true))
    end

    it "flips the names that hold the registered definition, not a later redefinition", :aggregate_failures do
      runtime.privatize(6, owner, :shown)
      owner.class_eval do
        alias_method :before, :shown
        def shown = before + 1
      end
      runtime.active = 6
      expect(owner.private_method_defined?(:before)).to(be(true))
      expect(owner.public_method_defined?(:shown)).to(be(true))
      runtime.active = nil
      expect(owner.public_method_defined?(:before)).to(be(true))
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
