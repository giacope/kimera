# frozen_string_literal: true

require "kimera/execution/baseline_failure"

# What a red baseline says about a test lost with its worker.
RSpec.describe(Kimera::Execution::BaselineFailure) do
  it "prints a lost test's stacks in full, after its truncated message", :aggregate_failures do
    stacks = "threads:\n#{"frame\n" * 80}end"
    message = described_class.summary(%w[t1], { "t1" => "x" * 400 }, "cmd", stacks: { "t1" => stacks })

    expect(message).to(include("#{"x" * 300}…\n    threads:\n    frame\n"))
    expect(message).to(include("    frame\n    end\n  reproduce without kimera: cmd"))
  end

  it "prints no stacks for a test that has none" do
    message = described_class.summary(%w[t1], { "t1" => "boom" }, "cmd")
    expect(message).to(eq("baseline suite is not green: t1\n  t1:\n    boom\n  reproduce without kimera: cmd"))
  end

  it "builds with stacks" do
    error = described_class.build(%w[t1], { "t1" => "boom" }, "cmd", stacks: { "t1" => "trace" })
    expect(error.message).to(include("    boom\n    trace\n"))
  end

  it "says when a test was also lost alone", :aggregate_failures do
    expect(described_class.relapsed(:timeout)).to(end_with("before reporting a result, and again when rerun alone"))
    expect(described_class.lost(:crash)).to(eq("its worker died before reporting a result"))
  end
end
