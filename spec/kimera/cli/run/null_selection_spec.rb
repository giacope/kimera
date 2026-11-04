# frozen_string_literal: true

require "kimera/cli/run/null_selection"
require "kimera/registry/builder"

RSpec.describe(Kimera::CLI::Run::NullSelection) do
  let(:registry) { Kimera::RegistryScan.new.source("def a(x, y) = x > y\n", file: "calc.rb") }

  it "selects every mutant and file, and announces nothing" do
    io = StringIO.new
    everything = described_class.new
    everything.announce(io, [1], 1)
    expect([everything.ids(registry), everything.files(%w[a.rb]), everything.narrowed(registry), io.string])
      .to(eq([registry.index.keys, %w[a.rb], registry, ""]))
  end
end
