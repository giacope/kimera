# frozen_string_literal: true

RSpec.describe Ledger::OverdraftGuard do
  it "falls back to the default limit when unset" do
    described_class.limit = nil
    expect(described_class.limit).to eq(5_000)
  end

  context "with a tight limit" do
    # Never reset: every example that cares sets the limit it needs.
    before { described_class.limit = 1_000 }

    let(:account) { Ledger::Account.new("cy", balance: 125) }

    it "lets the balance go negative within the limit" do
      expect(account.withdraw(500)).to eq(-375)
      expect(account).to be_overdrawn
      expect(account.history.last).to eq([:overdraft, 500])
    end

    it "allows a shortfall exactly at the limit" do
      expect(account.withdraw(1_100)).to eq(-1_000)
    end

    it "refuses a shortfall past the limit" do
      expect { account.withdraw(1_101) }.to raise_error(Ledger::InsufficientFunds, /exceeds 1000/)
      expect(account.balance).to eq(125)
    end

    it "reports headroom" do
      expect(account.headroom).to eq(1_125)
    end
  end

  it "sits in front of Account#withdraw" do
    expect(Ledger::Account.ancestors.index(described_class)).to be < Ledger::Account.ancestors.index(Ledger::Account)
  end
end
