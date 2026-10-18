# frozen_string_literal: true

RSpec.describe OrderFlow do
  let(:order) { described_class.new(100) }

  def journal_for(order)
    described_class.journal.select { |id, *| id == order.object_id }.map { |_, *rest| rest }
  end

  describe "happy path" do
    it "goes from pending to delivered" do
      expect(order.pay(120)).to be(true)
      expect(order.change_due).to eq(20)
      order.ship
      order.deliver
      expect(order.state).to eq(:delivered)
      expect(order).to be_final
      expect(journal_for(order)).to eq([%i[pay paid], %i[ship shipped], %i[deliver delivered]])
    end

    it "offers the events of the current state" do
      expect(order.available_events).to eq(%i[pay cancel])
      order.pay(100)
      expect(order.available_events).to eq(%i[ship refund])
      expect(order).not_to be_final
    end

    it "can be cancelled before payment" do
      expect(order.cancel).to be(true)
      expect(order.state).to eq(:cancelled)
      expect(order.available_events).to eq([])
    end
  end

  context "when lenient" do
    before { described_class.strict = false }

    it "refuses underpayment and journals the refusal" do
      expect(order.pay(99)).to be(false)
      expect(order.state).to eq(:pending)
      expect(journal_for(order)).to eq([%i[pay rejected]])
    end

    it "refuses events that do not apply" do
      expect(order.ship).to be(false)
    end

    it "refunds inside the window only" do
      described_class.refund_window_days = 14
      late = described_class.new(50)
      late.pay(50)
      expect(late.refund(15)).to be(false)
      order.pay(100)
      expect(order.refund(14)).to be(true)
      expect(order.paid_amount).to eq(0)
      expect(order.state).to eq(:refunded)
    end

    it "always refunds a lost parcel" do
      described_class.refund_window_days = 14
      order.pay(100)
      order.ship
      order.lose
      expect(order.refund(400)).to be(true)
    end
  end

  context "when strict" do
    # let! runs before each example and leaves the class strict afterwards.
    let!(:strict) { described_class.strict = true }

    it "raises on an illegal event" do
      expect { order.deliver }.to raise_error(OrderFlow::InvalidTransition, "cannot deliver when pending")
    end

    it "raises when a guard refuses" do
      expect { order.pay(1) }.to raise_error(OrderFlow::InvalidTransition, "can_pay? refused")
    end
  end

  describe ".replay" do
    before { described_class.strict = false }

    it "runs a script of events" do
      expect(described_class.replay(80, "pay:80 ship deliver").state).to eq(:delivered)
    end

    it "stops at the first refusal" do
      replayed = described_class.replay(80, "pay:10 pay:90 ship")
      expect(replayed.state).to eq(:pending)
      expect(journal_for(replayed)).to eq([%i[pay rejected]])
    end

    it "rejects unknown events" do
      expect { described_class.replay(80, "pay:80 teleport") }.to raise_error(ArgumentError, /teleport/)
    end
  end
end
