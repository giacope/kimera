# frozen_string_literal: true

require "kimera/execution/overlaying"

RSpec.describe(Kimera::Execution::Overlaying) do
  subject(:overlaying) { described_class.new }

  it "is overlaying only while its block runs" do
    inside = overlaying.overlay { overlaying.overlaying? }
    expect([overlaying.overlaying?, inside, overlaying.overlaying?]).to(eq([false, true, false]))
  end

  it "answers its block's value" do
    expect(overlaying.overlay { :answer }).to(eq(:answer))
  end

  it "stops overlaying when its block raises", :aggregate_failures do
    expect { overlaying.overlay { raise(ArgumentError, "boom") } }.to(raise_error(ArgumentError, "boom"))
    expect(overlaying).not_to(be_overlaying)
  end

  it "is the overlay the framework hooks ask" do
    expect(Kimera::Execution.const_get(:OVERLAYING)).to(be_a(described_class))
  end
end
