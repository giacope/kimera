require_relative "../lib/quote"

RSpec.describe Quote do
  it "warms the cache" do
    %i[eu us gb ch fr].each do |region|
      Quote.rate(region)
      Quote.exempt?(region)
    end
  end

  it("charges 20 in the EU") { expect(Quote.rate(:eu)).to eq(20) }
  it("charges 5 elsewhere") { expect(Quote.rate(:us)).to eq(5) }
  it("exempts Britain") { expect(Quote.exempt?(:gb)).to be(true) }
  it("exempts Switzerland") { expect(Quote.exempt?(:ch)).to be(true) }
  it("does not exempt France") { expect(Quote.exempt?(:fr)).to be(false) }
end
