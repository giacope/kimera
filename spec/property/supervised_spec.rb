# frozen_string_literal: true

require_relative "property_helper"

# The harness the pool properties lean on for their termination bound.
RSpec.describe(Supervised) do
  # A killed orphan can linger as a zombie until init reaps it; it isn't running.
  def running?(pid)
    Process.kill(0, pid)
    !File.read("/proc/#{pid}/status").match?(/^State:\s+Z/)
  rescue Errno::ESRCH, Errno::ENOENT
    false
  end

  it "returns what the block returns" do
    expect(described_class.run(deadline: 5) { { events: [[:result, 1]] } }).to(eq(events: [[:result, 1]]))
  end

  it "reports a block that raised" do
    expect(described_class.run(deadline: 5) { raise(ArgumentError, "boom") }.detail).to(eq("ArgumentError: boom"))
  end

  it "stops a block that never finishes, with everything it forked, at its deadline", :aggregate_failures do
    reader, writer = IO.pipe
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    expect { described_class.run(deadline: 0.5) { writer.puts(fork { sleep(60) }) || sleep(60) } }
      .to(raise_error(Supervised::Overdue))
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to(be < 5)
    writer.close
    grandchild = Integer(reader.read)
    expect(running?(grandchild)).to(be(false))
  ensure
    reader&.close
  end

  it "carries a report larger than a pipe buffer" do
    expect(described_class.run(deadline: 5) { "x" * 1_000_000 }.size).to(eq(1_000_000))
  end
end
