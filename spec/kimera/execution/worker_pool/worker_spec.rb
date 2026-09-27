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

  it "is fresh until it claims a mutant", :aggregate_failures do
    worker = described_class.new(pid: 1)
    expect(worker.fresh?).to(be(true))
    worker.claim(5, 1.0)
    expect(worker.fresh?).to(be(false))
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

  it "takes an autopsy only from an armed worker", :aggregate_failures do
    stacks = Object.new
    stacks.define_singleton_method(:take) { |pid| "dump #{pid}" }

    expect(described_class.new(pid: 42, stacks: stacks).autopsy).to(eq("dump 42"))
    expect(described_class.new(pid: 42).autopsy).to(be_nil)
  end
end
