# frozen_string_literal: true

RSpec.describe(Kimera::Runtime) do
  after { described_class.reset! }

  describe ".active / .active?" do
    it "selects the original when active is nil", :aggregate_failures do
      described_class.active = nil
      expect(described_class.active?(1)).to(be(false))
      expect(described_class.active?(2)).to(be(false))
    end

    it "selects exactly one mutant", :aggregate_failures do
      described_class.active = 2
      expect(described_class.active?(1)).to(be(false))
      expect(described_class.active?(2)).to(be(true))
    end

    it "coerces the active id to an Integer", :aggregate_failures do
      described_class.active = "7"
      expect(described_class.active).to(eq(7))
      expect(described_class.active?(7)).to(be(true))
    end
  end

  describe ".reset!" do
    it "deselects the active mutant", :aggregate_failures do
      described_class.active = 5
      described_class.reset!
      expect(described_class.active).to(be_nil)
      expect(described_class.active?(5)).to(be(false))
    end
  end

  # Assert only through our own handles: when self-hosted, an outer harness
  # holds a ledger open for the whole run.
  describe "coverage touch-ledgers" do
    def touches
      ledger = described_class.start!
      [10, 11, 10].each { |mutant| described_class.active?(mutant) }
      [described_class.drain!(ledger), described_class.drain!(ledger)]
    ensure
      described_class.stop!(ledger)
    end

    it "records touches on an open ledger and drains them uniquely", :aggregate_failures do
      touches = self.touches
      expect(touches.first).to(contain_exactly(10, 11))
      expect(touches.last).to(eq([])) # draining clears the ledger
    end

    it "stops recording on a ledger once it is closed" do
      ledger = described_class.start!
      described_class.stop!(ledger)
      described_class.active?(5)
      expect(ledger).to(be_empty)
    end

    def close(ledger, mutant)
      described_class.stop!(ledger)
      described_class.active?(mutant)
      ledger
    end

    def nested
      outer, inner = Array.new(2) { described_class.start! }
      described_class.active?(7)
      # Drain before close stops the ledger.
      drain = described_class.drain!(inner)

      close(inner, 8)
      [drain, described_class.drain!(outer)]
    ensure
      [outer, inner].each { |ledger| described_class.stop!(ledger) }
    end

    it "records on every open ledger, so nested measurers cannot steal touches", :aggregate_failures do
      drains = nested
      expect(drains.first).to(eq([7]))
      expect(drains.last).to(contain_exactly(7, 8))
    end

    # Drained ledgers are equal empty arrays, so Array#delete would evict the
    # outer one too. Self-hosted, that zeroed coverage for later examples.
    def drain(mutant, ledger)
      described_class.active?(mutant)
      described_class.drain!(ledger)
    end

    def fresh
      ledger = described_class.start!
      described_class.drain!(ledger)
      ledger
    end

    def isolation
      outer = described_class.start!
      drain(1, outer) # outer now == []
      close(fresh, 2) # inner also == []; must keep the empty outer
      described_class.drain!(outer)
    ensure
      described_class.stop!(outer)
    end

    it "closes only the given ledger, even when both are drained to empty" do
      expect(isolation).to(eq([2]))
    end

    # Start from an empty table: an outer measurer or leaked ledgers would
    # skip the nil-teardown path.
    def preserve
      saved = described_class.instance_variable_get(:@ledgers)
      described_class.instance_variable_set(:@ledgers, nil)
      yield
    ensure
      described_class.instance_variable_set(:@ledgers, saved)
    end

    it "tolerates closing a ledger when no coverage pass is active" do
      preserve do
        ledger = described_class.start!
        described_class.stop!(ledger)
        expect { described_class.stop!(ledger) }.not_to(raise_error)
      end
    end

    # White-box: an empty array would stay on active?'s hot path forever.
    it "frees the ledger table when the last ledger closes" do
      preserve do
        ledger = described_class.start!
        described_class.stop!(ledger)
        expect(described_class.instance_variable_get(:@ledgers)).to(be_nil)
      end
    end

    # Self-hosted suites call reset! in hooks; the harness's touches must survive.
    def reset
      ledger = described_class.start!
      described_class.active?(3)
      described_class.reset!
      described_class.active?(4)
      described_class.drain!(ledger)
    ensure
      described_class.stop!(ledger)
    end

    it "keeps open ledgers (and their contents) across reset!" do
      expect(reset).to(contain_exactly(3, 4))
    end
  end
end
