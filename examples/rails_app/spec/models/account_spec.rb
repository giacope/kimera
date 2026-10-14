RSpec.describe Account do
  it "is premium with enough credit unless suspended" do
    expect([accounts(:alice), accounts(:bob), accounts(:carol)].map(&:premium?)).to eq([true, false, false])
    expect(described_class.new(credit_cents: 10_000)).to be_premium
  end

  it "refuses charges it cannot cover" do
    expect { accounts(:bob).charge!(3_001) }.to raise_error(Account::InsufficientCredit)
    expect { accounts(:bob).charge!(0) }.to raise_error(ArgumentError)
  end

  it "charges exactly its credit" do
    accounts(:bob).charge!(3_000)
    expect(accounts(:bob).reload.credit_cents).to eq(0)
  end

  it "validates the email" do
    expect(described_class.new(email: "nobody", credit_cents: 0)).not_to be_valid
    expect(described_class.create!(email: " Eve@Example.com", credit_cents: 0).email).to eq("eve@example.com")
  end
end
