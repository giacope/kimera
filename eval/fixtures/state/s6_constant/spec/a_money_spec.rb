require_relative "../lib/money"

RSpec.describe Money do
  it("formats dollars") { expect(Money.format(150)).to eq("$1.50") }
  it("knows round amounts") { expect(Money.round?(300)).to be(true) }
  it("knows uneven amounts") { expect(Money.round?(301)).to be(false) }
  it("does not call zero round") { expect(Money.round?(0)).to be(false) }
end
