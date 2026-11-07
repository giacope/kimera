# frozen_string_literal: true

require_relative "property_helper"

RSpec.describe(Supervised) do
  def running?(pid)
    Process.kill(0, pid)
    !File.read("/proc/#{pid}/status").match?(/^State:\s+Z/)
  rescue Errno::ESRCH, Errno::ENOENT
    false
  end

  def outlives?(pid)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1
    sleep(0.01) while running?(pid) && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
    running?(pid)
  end

  it "returns what the block returns" do
    expect(described_class.run(deadline: 5) { { events: [[:result, 1]] } }).to(eq(events: [[:result, 1]]))
  end

  it "reports a block that raised" do
    expect(described_class.run(deadline: 5) { raise(ArgumentError, "boom") }.detail).to(eq("ArgumentError: boom"))
  end

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
    expect(outlives?(grandchild)).to(be(false))
  end

  def ensured(writer)
    sleep(60)
  ensure
    writer.puts("stopped")
  end

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
