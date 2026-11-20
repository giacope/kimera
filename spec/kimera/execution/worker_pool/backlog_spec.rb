# frozen_string_literal: true

require "kimera/execution/worker_pool"

RSpec.describe(Kimera::Execution::WorkerPool::Backlog) do
  it "gives the queue's ids in order", :aggregate_failures do
    backlog = described_class.new([1, 2])
    expect([backlog.take, backlog.take]).to(eq([1, 2]))
  end

  it "has nothing to give once the queue runs dry" do
    expect(described_class.new([]).take).to(be_nil)
  end

  it "skips a finished id in the queue" do
    backlog = described_class.new([1, 2])
    backlog.done!(1)
    expect(backlog.take).to(eq(2))
  end

  it "has no work left once the queue holds only finished ids" do
    backlog = described_class.new([1])
    backlog.done!(1)
    expect(backlog.pending?).to(be(false))
  end

  it "counts an unfinished id in the queue as work left" do
    expect(described_class.new([1]).pending?).to(be(true))
  end

  it "leaves the queue it was given alone" do
    queue = [1, 2]
    described_class.new(queue).take
    expect(queue).to(eq([1, 2]))
  end
end
