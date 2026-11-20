# frozen_string_literal: true

require "fileutils"
require "kimera/synthesis/overlay"
require "tmpdir"

RSpec.describe(Kimera::Overlay::Source) do
  let(:seen) { stub_const("KimeraSourceSeen", {}) }

  def evaluated(code, file) = seen.then { described_class.new(code).evaluate(file) }

  it "gives each file its own top-level locals", :aggregate_failures do
    evaluated("limit = 10\nKimeraSourceSeen[:first] = -> { limit }\n", "first.rb")
    evaluated("limit = 20\nKimeraSourceSeen[:second] = -> { limit }\n", "second.rb")
    expect(seen.transform_values(&:call)).to(eq(first: 10, second: 20))
    expect(TOPLEVEL_BINDING.local_variable_defined?(:limit)).to(be(false))
  end

  it "sees none of the main script's top-level locals" do
    evaluated("KimeraSourceSeen[:locals] = binding.local_variables\n", "first.rb")
    expect(seen[:locals]).to(eq([]))
  end

  it "runs with its path as __FILE__ and __dir__, and requires relative to it" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "dep.rb"), "KimeraSourceSeen[:dep] = true\n")
      evaluated("require_relative 'dep'\nKimeraSourceSeen[:at] = [__FILE__, __dir__]\n", File.join(dir, "first.rb"))
      expect(seen).to(eq(dep: true, at: [File.join(dir, "first.rb"), dir]))
    end
  end

  it "honors the file's magic comments" do
    evaluated("# frozen_string_literal: true\nKimeraSourceSeen[:frozen] = 'x'.frozen?\n", "first.rb")
    expect(seen[:frozen]).to(be(true))
  end
end
