require_relative "../lib/tally"

RSpec.describe Tally do
  it("counts the evens below three million") { expect(Tally.evens(3_000_000)).to eq(1_500_000) }
end
