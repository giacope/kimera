# frozen_string_literal: true

require "fileutils"
require "kimera/synthesis/overlay"
require "tmpdir"

# An overlaid file runs as `load` runs it: at the top level, with a scope of
# its own, its own __FILE__ and __dir__, and require_relative from where it
# lies.
RSpec.describe(Kimera::Overlay::Source) do
  # Each file stores what it saw in this hash, so no constant is left behind.
  let(:seen) { {} }

  before { stub_const("KimeraSourceSeen", seen) }

  it "gives each file its own top-level locals", :aggregate_failures do
    described_class.new("limit = 10\nKimeraSourceSeen[:first] = -> { limit }\n").evaluate("first.rb")
    described_class.new("limit = 20\nKimeraSourceSeen[:second] = -> { limit }\n").evaluate("second.rb")
    expect(seen.transform_values(&:call)).to(eq(first: 10, second: 20))
    expect(TOPLEVEL_BINDING.local_variable_defined?(:limit)).to(be(false))
  end

  it "sees none of the main script's top-level locals" do
    described_class.new("KimeraSourceSeen[:locals] = binding.local_variables\n").evaluate("first.rb")
    expect(seen[:locals]).to(eq([]))
  end

  it "runs with its path as __FILE__ and __dir__, and requires relative to it" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "dep.rb"), "KimeraSourceSeen[:dep] = true\n")
      described_class.new("require_relative 'dep'\nKimeraSourceSeen[:at] = [__FILE__, __dir__]\n")
        .evaluate(File.join(dir, "first.rb"))
      expect(seen).to(eq(dep: true, at: [File.join(dir, "first.rb"), dir]))
    end
  end

  it "honors the file's magic comments" do
    described_class.new("# frozen_string_literal: true\nKimeraSourceSeen[:frozen] = 'x'.frozen?\n").evaluate("first.rb")
    expect(seen[:frozen]).to(be(true))
  end
end
