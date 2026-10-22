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

  # Runs, past its deadline, a block that forks a sleeping grandchild and then
  # sleeps; how long that took, and the grandchild.
  def overdue
    IO.pipe do |reader, writer|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      expect { described_class.run(deadline: 0.5) { writer.puts(fork { sleep(60) }) || sleep(60) } }
        .to(raise_error(Supervised::Overdue))
      writer.close
      [Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, Integer(reader.read)]
    end
  end

  it "stops a block that never finishes, with everything it forked, at its deadline", :aggregate_failures do
    took, grandchild = overdue
    expect(took).to(be < 5)
    expect(running?(grandchild)).to(be(false))
  end

  def ensured(writer)
    sleep(60)
  ensure
    writer.puts("stopped")
  end

  # The pool's workers lead process groups of their own; only its ensure can
  # stop them.
  it "lets an overdue block's ensures run before it is killed", :aggregate_failures do
    IO.pipe do |reader, writer|
      expect { described_class.run(deadline: 0.5) { ensured(writer) } }.to(raise_error(Supervised::Overdue))
      writer.close
      expect(reader.read).to(eq("stopped\n"))
    end
  end

  it "carries a report larger than a pipe buffer" do
    expect(described_class.run(deadline: 5) { "x" * 1_000_000 }.size).to(eq(1_000_000))
  end
end
