# frozen_string_literal: true

require "kimera/execution/baseline_failure"
require "kimera/execution/baseline_losses"

RSpec.describe(Kimera::Execution::BaselineFailure::Summary) do
  def context(stacks) = described_class::Context.new(workers: {}, stacks: stacks, jobs: 1, ordered: [])

  it "prints a lost test's stacks in full, after its truncated message", :aggregate_failures do
    stacks = "threads:\n#{"frame\n" * 80}end"
    message = described_class.new(%w[t1], { "t1" => "x" * 400 }, "cmd", context("t1" => [stacks])).to_s

    expect(message).to(include("#{"x" * 300}…\n    threads:\n    frame\n"))
    expect(message).to(include("    frame\n    end\n  reproduce without kimera: cmd"))
  end

  it "prints no stacks for a test that has none" do
    message = described_class.new(%w[t1], { "t1" => "boom" }, "cmd").to_s
    expect(message).to(eq("baseline suite is not green: t1\n  t1:\n    boom\n  reproduce without kimera: cmd"))
  end

  it "prints a test's stacks under its message" do
    message = described_class.new(%w[t1], { "t1" => "boom" }, "cmd", context("t1" => ["trace"])).to_s
    expect(message).to(include("    boom\n    trace\n"))
  end

  it "says when a test was also lost alone", :aggregate_failures do
    losses = Kimera::Execution::BaselineLosses.new
    expect(losses.charge("t1", :crash, [])).to(eq("its worker died before reporting a result"))
    losses.stall("t1", [])
    expect(losses.charge("t1", :timeout, [])).to(end_with("before reporting a result, and again when rerun alone"))
  end
end
