require_relative "../lib/mutant_runtime"

RSpec.describe MutantRuntime do
  it("is active under a minute") { expect(MutantRuntime.active?(59)).to be(true) }
  it("is idle from a minute") { expect(MutantRuntime.active?(60)).to be(false) }
end
