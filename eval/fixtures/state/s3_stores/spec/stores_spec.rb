require_relative "../lib/stores"

RSpec.describe "memoized grades" do
  it("letters 95 as A") { expect(letter_for(95)).to eq("A") }
  it("letters 90 as A") { expect(letter_for(90)).to eq("A") }
  it("letters 85 as B") { expect(letter_for(85)).to eq("B") }
  it("letters 80 as B") { expect(letter_for(80)).to eq("B") }
  it("letters 70 as C") { expect(letter_for(70)).to eq("C") }
  it("passes 60") { expect(Transcript.passing?(60)).to be(true) }
  it("passes 100") { expect(Transcript.passing?(100)).to be(true) }
  it("fails 59") { expect(Transcript.passing?(59)).to be(false) }
  it("fails 101") { expect(Transcript.passing?(101)).to be(false) }
  it("labels 75 a pass") { expect(Labels.for(75)).to eq("pass") }
  it("labels 20 a fail") { expect(Labels.for(20)).to eq("fail") }
end
