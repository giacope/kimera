require_relative "../lib/cache"

RSpec.describe Cache do
  it("charges the high rate above 10") { expect(Cache.get(11)).to eq(2) }
  it("charges the low rate at 10") { expect(Cache.get(10)).to eq(1) }
end
