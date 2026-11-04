# frozen_string_literal: true

require "kimera/execution/clock"

RSpec.describe(Kimera::Execution::Clock) do
  it "reads the monotonic clock unless given another", :aggregate_failures do
    monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    expect(described_class.new(0).now).to(be_within(1).of(monotonic))
    expect(described_class.new(0, Process::CLOCK_REALTIME).now).to(be_within(5).of(Time.now.to_f))
  end

  it "pauses for its interval" do
    clock = described_class.new(0.05)
    started = clock.now
    clock.pause
    expect(clock.now - started).to(be >= 0.05)
  end
end
