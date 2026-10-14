require_relative "../lib/flags"
require_relative "../lib/price"

RSpec.describe Flags do
  it "serves prices from the table while the flag is on" do
    Flags.with("PRICE_TABLE", "1") { expect(Price.of(3)).to eq(27) }
  end

  it "sets the variable inside the block" do
    Flags.with("KIMERA_EVAL_FLAG", "x") { expect(ENV.fetch("KIMERA_EVAL_FLAG")).to eq("x") }
  ensure
    ENV.delete("KIMERA_EVAL_FLAG")
  end

  it "restores the variable after the block" do
    Flags.with("KIMERA_EVAL_FLAG", "x") { nil }
    expect(ENV.key?("KIMERA_EVAL_FLAG")).to be(false)
  ensure
    ENV.delete("KIMERA_EVAL_FLAG")
  end
end
