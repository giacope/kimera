require_relative "../lib/gate"

RSpec.describe Gate do
  it("opens under load") { expect(Gate.open?(20)).to be(true) }
  it("stays shut at 5") { expect(Gate.open?(5)).to be(false) }
  it("opens at 50") { expect(Gate.open?(50)).to be(true) }
  it("shuts above 50") { expect(Gate.open?(51)).to be(false) }
end
