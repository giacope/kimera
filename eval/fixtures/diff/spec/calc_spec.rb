require_relative "../lib/calc"

RSpec.describe Calc do
  it("alpha") { expect([Calc.alpha(2), Calc.alpha(1)]).to eq([true, false]) }
  it("beta") { expect([Calc.beta(1), Calc.beta(2)]).to eq([true, false]) }
  it("gamma") { expect([Calc.gamma(3), Calc.gamma(4)]).to eq([true, false]) }
end
