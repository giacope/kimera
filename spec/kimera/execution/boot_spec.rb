# frozen_string_literal: true

require "kimera/execution/boot"

RSpec.describe(Kimera::Execution::Boot) do
  # The suite loads into Kimera's own process, so a helper gating its coverage
  # floor on KIMERA must see it before the first file is required.
  it "sets KIMERA before loading the suite", :aggregate_failures do
    ENV.delete("KIMERA")
    seen = nil
    adapter = Object.new
    adapter.define_singleton_method(:source) { |_files| seen = ENV.fetch("KIMERA", nil) }
    adapter.define_singleton_method(:start) { :started }
    described_class.new(adapter: adapter, isolate: false).suite(["t.rb"])
    expect(seen).to(eq("1"))
    expect(ENV.fetch("KIMERA", nil)).to(eq("1"))
  end
end
