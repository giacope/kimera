# frozen_string_literal: true

RSpec.describe Ledger::Audit do
  # Prepends Audit for the rest of the run; the other files do not care.
  before { Ledger.enable_audit! }

  it "only prepends once" do
    expect(Ledger.enable_audit!).to be(false)
    expect(Ledger::Account.ancestors.first).to eq(described_class)
  end

  it "logs deposits" do
    account = Ledger::Account.new("dee", balance: 10)
    account.deposit(90)
    expect(described_class.log.last).to eq("dee +90 => 100")
  end

  it "logs the full amount taken by a withdrawal, fee included" do
    account = Ledger::Account.new("eve", balance: 3_000)
    account.withdraw(1_000)
    expect(described_class.log.last).to eq("eve -1025 => 1975")
  end
end
