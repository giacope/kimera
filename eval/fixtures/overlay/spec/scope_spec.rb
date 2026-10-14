require_relative "../lib/first"
require_relative "../lib/second"

RSpec.describe "top-level locals in two files" do
  it("keeps the first file's limit") { expect([First.over?(11), First.over?(10)]).to eq([true, false]) }
  it("keeps the second file's limit") { expect([Second.over?(21), Second.over?(20)]).to eq([true, false]) }
  it("reads a path relative to its file") { expect(Second.name).to eq("second") }
end
