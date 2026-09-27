# frozen_string_literal: true

require "kimera/execution/baseline_stall"

# Baseline tests that stalled under parallel load but passed alone.
RSpec.describe(Kimera::Execution::BaselineStall) do
  def text(recovered) = described_class.new(recovered, hard: 16.0, jobs: 8).to_s

  it "says nothing when no test stalled" do
    expect(text({})).to(be_nil)
  end

  it "names the stalled tests, the limit and the load, then advises", :aggregate_failures do
    lines = text({ "A#t" => nil, "B#t" => nil }).lines(chomp: true)

    expect(lines.first).to(
      eq(
        "kimera: 2 baseline test(s) hit the hard timeout (16.0s) with 8 workers running, " \
          "then passed when rerun alone: A#t, B#t"
      )
    )
    expect(lines.last).to(
      eq(
        "  flaky under parallel load: mutants they cover can time out the same way. If they are only slow, " \
          "raise --hard-timeout; if they wait on something the workers share, give each worker its own"
      )
    )
  end

  it "indents each test's stacks under it" do
    expect(text({ "A#t" => "threads:\nmain" })).to(end_with("\n  A#t:\n    threads:\n    main"))
  end

  it "shows at most three tests' stacks", :aggregate_failures do
    recovered = (1..5).to_h { |i| ["T#{i}", "stack #{i}"] }
    shown = text(recovered)

    expect(shown).to(include("stack 3"))
    expect(shown).not_to(include("stack 4"))
  end
end
