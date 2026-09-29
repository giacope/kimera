# frozen_string_literal: true

require "json"
require "kimera/execution/worker_pool"

RSpec.describe Kimera::Execution::WorkerPool::Worker do
  context "without a deadline" do
    it "never expires" do
      expect(described_class.new.expired?(10.0)).to(be_nil)
    end
  end

  context "with a deadline" do
    subject(:worker) { described_class.new(deadline: 10.0) }

    it "expires exactly when no positive interval remains", :aggregate_failures do
      expect(worker.expired?(9.9)).to(be(false))
      expect(worker.expired?(10.0)).to(be(true))
      expect(worker.expired?(10.1)).to(be(true))
    end
  end

  it "hands back only whole lines and keeps the rest for the next chunk", :aggregate_failures do
    worker = described_class.new
    expect(worker.lines("a\nb")).to(eq(["a"]))
    expect(worker.lines("c\n\nd\n")).to(eq(["bc", "", "d"]))
    expect(worker.rest).to(eq(""))
    expect(worker.lines("e")).to(eq([]))
    expect([worker.rest, worker.rest]).to(eq(["e", ""]))
  end

  it "is fresh until it claims a mutant", :aggregate_failures do
    worker = described_class.new(pid: 1)
    expect(worker.fresh?).to(be(true))
    worker.claim(5, 1.0)
    expect(worker.fresh?).to(be(false))
  end

  # Teardown hooks can hang on locks a leaked thread holds; the watchdog must still see it.
  it "stays on the clock while it retires", :aggregate_failures do
    worker = described_class.new(request: :pipe, inflight: 5, deadline: nil)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    expect(worker.retire(3.0)).to(eq(:pipe))
    expect(worker.inflight).to(be_nil)
    expect(worker.deadline).to(be_within(1.0).of(started + 3.0))
    expect(worker.expired?(started + 4.0)).to(be(true))
  end

  it "offers a recheck with its flag, and plain work without one" do
    reader, writer = IO.pipe
    worker = described_class.new(request: writer)
    worker.offer(5, recheck: true)
    worker.offer(6)
    writer.close

    expect(reader.each_line.map { |line| JSON.parse(line) }).to(eq([{ "id" => 5, "recheck" => true }, { "id" => 6 }]))
  ensure
    reader&.close
  end

  # Any line proves the worker alive; a crash line also says why it is dying.
  it "renews its deadline on every message and keeps a crash's last words", :aggregate_failures do
    worker = described_class.new
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    expect(worker.heard({ "t" => "tick" }, 3.0)).to(equal(worker))
    expect(worker.deadline).to(be_within(1.0).of(started + 3.0))
    expect(worker.last_words).to(be_nil)
    worker.heard({ "t" => "requeue", "detail" => "state leak" }, 3.0)
    expect(worker.last_words).to(be_nil)
    worker.heard({ "t" => "crash", "detail" => "Boom: x" }, 3.0)
    expect(worker.last_words).to(eq("Boom: x"))
  end

  describe "#obituary" do
    def status(fate)
      pid = fork { fate == :signal ? Process.kill("TERM", Process.pid) && sleep(1) : exit!(3) }
      Process.wait2(pid).last
    end

    it "says how the worker died, then what it said last", :aggregate_failures do
      worker = described_class.new(last_words: "SignalException: SIGTERM")
      expect(worker.obituary(status(:signal))).to(eq("died on signal 15 (SIGTERM)\nSignalException: SIGTERM"))
      expect(described_class.new.obituary(status(:exit))).to(eq("exited 3"))
    end

    it "has only the last words for a worker that could not be reaped, and nothing without them", :aggregate_failures do
      expect(described_class.new(last_words: "Boom: x").obituary(nil)).to(eq("Boom: x"))
      expect(described_class.new.obituary(nil)).to(be_nil)
    end
  end

  it "takes an autopsy only from an armed worker", :aggregate_failures do
    stacks = Object.new
    stacks.define_singleton_method(:take) { |pid| "dump #{pid}" }

    expect(described_class.new(pid: 42, stacks: stacks).autopsy).to(eq("dump 42"))
    expect(described_class.new(pid: 42).autopsy).to(be_nil)
  end
end
