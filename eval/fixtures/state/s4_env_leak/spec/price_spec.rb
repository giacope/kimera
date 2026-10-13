require_relative "../lib/price"

RSpec.describe Price do
  it("charges 10 each for two") { expect(Price.of(2)).to eq(20) }
  it("discounts three") { expect(Price.of(3)).to eq(27) }
  it("discounts four") { expect(Price.of(4)).to eq(36) }
end
