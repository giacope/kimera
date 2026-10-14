require_relative "../lib/plugins"

RSpec.describe Plugins do
  it "returns the plugin it registers" do
    expect(Plugins.register("legacy", enabled: false).name).to eq("legacy")
  end
end
