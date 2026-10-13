require_relative "../lib/order_tax"

RSpec.describe Order do
  it "sums lines" do
    expect(Order.new([[100, 2], [50, 1]]).subtotal).to eq(250)
  end

  it "adds tax" do
    expect(Order.new([[100, 2], [50, 1]]).total).to eq(275)
    expect(Order.new([[999, 1]]).total).to eq(1098)
  end

  it "discounts from 1000 before tax" do
    expect(Order.new([[500, 2]]).total).to eq(990)
    expect(Order.new([[1001, 1]]).total).to eq(991)
  end

  it "handles empty orders" do
    expect(Order.new([]).total).to eq(0)
  end
end
