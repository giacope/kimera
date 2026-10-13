require_relative "../lib/plugins"

RSpec.describe Plugins do
  it("lists the enabled plugins") { expect(Plugins.names).to eq(["core"]) }
  it("counts the enabled plugins") { expect(Plugins.count).to eq(1) }
end
