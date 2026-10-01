# frozen_string_literal: true

require "kimera/execution/baseline_failure"

# thor's suite, red on four workers, used to print about 80 test IDs on one
# line before its per-worker traces.
RSpec.describe(Kimera::Execution::BaselineFailure::Summary) do
  let(:failed) { (1..80).map { |n| "./spec/thor_spec.rb[1:#{n}]" } }

  let(:workers) { failed.each_slice(20).with_index.to_h { |ids, slot| [slot, ids] } }

  def message(jobs: 4)
    context = described_class::SERIAL.with(workers: workers, jobs: jobs)
    described_class.new(failed, failed.to_h { |id| [id, "Errno::ENOENT"] }, "cmd", context).to_s
  end

  it "lists the first ten failing tests, one per line, then how many more", :aggregate_failures do
    listed = failed.first(10).map { |id| "\n    #{id}" }.join
    expect(message).to(start_with("baseline suite is not green: 80 tests failed:#{listed}\n    … and 70 more\n  "))
  end

  it "names one failing test, or none, on the summary line, and lists two or more", :aggregate_failures do
    expect(described_class.new(%w[a], {}, "cmd").listed).to(eq("a"))
    expect(described_class.new([], {}, "cmd").listed).to(eq(""))
    expect(described_class.new(%w[a b], {}, "cmd").listed).to(eq("2 tests failed:\n    a\n    b"))
  end

  it "keeps the whole error, per-worker lines included, to a screen", :aggregate_failures do
    lines = message.lines
    expect(lines.size).to(eq(1 + 11 + (3 * 2) + 1 + 4 + 2))
    expect(lines.grep(/worker \d: ran 20/).map { |line| line.scan("thor_spec").size }).to(all(be <= 5 + 3))
  end

  it "names --jobs 1 as the check only when the baseline ran on several workers", :aggregate_failures do
    expect(message.lines.last).to(eq("  ran on 4 workers: #{described_class::SHARED}"))
    expect(message(jobs: 1).lines.last).to(eq("  reproduce without kimera: cmd"))
    shared = "\n  ran on 2 workers: #{described_class::SHARED}"
    expect(described_class.new(%w[t1], {}, "cmd", described_class::SERIAL.with(jobs: 2)).to_s)
      .to(eq("baseline suite is not green: t1\n  reproduce without kimera: cmd#{shared}"))
  end
end
