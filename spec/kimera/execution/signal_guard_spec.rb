# frozen_string_literal: true

require "kimera/execution/signal_guard"

# A serial baseline runs tests in kimera's own process: a signal a test sends
# itself, with nothing trapping it, becomes that test's failure.
RSpec.describe(Kimera::Execution::SignalGuard) do
  it "returns what the run returns" do
    expect(described_class.run("t1") { :outcome }).to(eq(:outcome))
  end

  it "turns an untrapped signal into the test's failure", :aggregate_failures do
    outcome = described_class.run("t1") { raise(SignalException, "TERM") }
    expect(outcome.passed?).to(be(false))
    expect(outcome.failures.keys).to(eq(["t1"]))
    expect(outcome.failures["t1"]).to(start_with("SignalException: SIGTERM\nnothing trapped SIGTERM"))
  end

  it "lets an interrupt stop the run" do
    expect { described_class.run("t1") { raise(Interrupt) } }.to(raise_error(Interrupt))
  end
end
