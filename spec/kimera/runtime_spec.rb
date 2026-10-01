# frozen_string_literal: true

RSpec.describe(Kimera::Runtime) do
  let(:runtime) { described_class.new }

  it "is the one process-wide runtime that synthesized guards call as ::MutantRuntime" do
    expect(MutantRuntime).to(equal(Kimera::RUNTIME))
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
      expect(ledger).to(be_empty)
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
    # skip the nil-teardown path.
    def preserve
      saved = runtime.instance_variable_get(:@ledgers)
      runtime.instance_variable_set(:@ledgers, nil)
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

    # White-box: an empty array would stay on active?'s hot path forever.
    it "frees the ledger table when the last ledger closes" do
      preserve do
        ledger = runtime.start!
        runtime.stop!(ledger)
        expect(runtime.instance_variable_get(:@ledgers)).to(be_nil)
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
end
