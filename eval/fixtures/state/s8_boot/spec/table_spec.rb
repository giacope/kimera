require_relative "../lib/table"

RSpec.describe Table do
  it("looks up the low rate at 10") { expect(Table.lookup(10)).to eq(1) }
  it("looks up the high rate at 11") { expect(Table.lookup(11)).to eq(2) }
  it("computes a low rate directly") { expect(Rate.compute(5)).to eq(1) }
end
