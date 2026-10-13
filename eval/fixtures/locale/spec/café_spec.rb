require_relative "../lib/café"

RSpec.describe Café do
  it("trouve 12 € « cher »") { expect(Café.libellé(12)).to eq("cher — 12 €") }
  it("trouve 5 € abordable ✓") { expect(Café.libellé(5)).to eq("abordable ✓") }
end
