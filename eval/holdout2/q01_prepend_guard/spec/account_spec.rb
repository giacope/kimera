# frozen_string_literal: true

RSpec.describe Ledger::Account do
  subject(:account) { described_class.new("ana", balance: 5_000) }

  describe "#deposit" do
    it "adds to the balance and returns it" do
      expect(account.deposit(250)).to eq(5_250)
      expect(account.balance).to eq(5_250)
      expect(account.history.last).to eq([:deposit, 250])
    end

    it "rejects zero and negative amounts" do
      expect { account.deposit(0) }.to raise_error(ArgumentError)
      expect { account.deposit(-5) }.to raise_error(ArgumentError)
      expect(account.balance).to eq(5_000)
    end
  end

  describe "#fee_for" do
    it "charges nothing below the threshold" do
      expect(account.fee_for(999)).to eq(0)
    end

    it "charges the minimum fee at the threshold" do
      expect(account.fee_for(1_000)).to eq(25)
    end

    it "charges the percentage once it beats the minimum" do
      expect(account.fee_for(2_000)).to eq(30)
      expect(account.fee_for(10_000)).to eq(150)
    end
  end

  describe "#withdraw" do
    it "takes small amounts without a fee" do
      expect(account.withdraw(500)).to eq(4_500)
      expect(account.history.last).to eq([:withdraw, 500])
    end

    it "adds the fee to larger withdrawals" do
      expect(account.withdraw(2_000)).to eq(2_970)
    end

    it "can empty the account exactly" do
      expect(account.withdraw(4_926)).to eq(0)
      expect(account).not_to be_overdrawn
    end

    it "rejects non-positive amounts" do
      expect { account.withdraw(0) }.to raise_error(ArgumentError)
    end
  end

  describe "#transfer" do
    it "moves money between accounts" do
      other = described_class.new("bo", balance: 100)
      expect(account.transfer(other, 400)).to eq([4_600, 500])
    end
  end
end
