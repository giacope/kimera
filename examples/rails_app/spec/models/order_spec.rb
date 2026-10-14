RSpec.describe Order do
  it "totals a small order at list price" do
    expect(accounts(:bob).orders.create!(quantity: 1).total_cents).to eq(2_500)
  end

  it "discounts ten or more by a fifth" do
    expect(described_class.new(quantity: 10, account: accounts(:bob)).discount_rate).to eq(0.2)
    expect(described_class.new(quantity: 9, account: accounts(:bob)).discount_rate).to eq(0.0)
  end

  it "discounts five or more for premium accounts only" do
    expect(described_class.new(quantity: 5, account: accounts(:alice)).discount_rate).to eq(0.1)
    expect(described_class.new(quantity: 4, account: accounts(:alice)).discount_rate).to eq(0.0)
    expect(described_class.new(quantity: 5, account: accounts(:bob)).discount_rate).to eq(0.0)
  end

  it "requires a positive quantity" do
    expect(described_class.new(quantity: 0, account: accounts(:bob))).not_to be_valid
  end

  it "enqueues a receipt" do
    expect { accounts(:alice).orders.create!(quantity: 2) }.to have_enqueued_job(ReceiptJob)
  end
end
