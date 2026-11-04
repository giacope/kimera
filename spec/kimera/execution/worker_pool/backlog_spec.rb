# frozen_string_literal: true

require "kimera/execution/worker_pool"

RSpec.describe(Kimera::Execution::WorkerPool::Backlog) do
  def worker(fresh:) = Struct.new(:fresh?).new(fresh)

  it "gives a recheck only to a worker that has run nothing yet", :aggregate_failures do
    backlog = described_class.new([1, 2])
    backlog.requeue(9)

    expect(backlog.take(worker(fresh: false))).to(eq([1, false]))
    expect(backlog.take(worker(fresh: true))).to(eq([9, true]))
    expect(backlog.take(worker(fresh: true))).to(eq([2, false]))
  end

  it "has nothing to give once the queue runs dry" do
    expect(described_class.new([]).take(worker(fresh: true))).to(eq([]))
  end

  it "skips a finished id in the queue" do
    backlog = described_class.new([1, 2])
    backlog.done!(1)
    expect(backlog.take(worker(fresh: false))).to(eq([2, false]))
  end

  it "flags a requeued id as a recheck however it comes back", :aggregate_failures do
    backlog = described_class.new([9])
    backlog.requeue(9)

    expect(backlog.take(worker(fresh: false))).to(eq([9, true]))
    expect(backlog.take(worker(fresh: true))).to(eq([9, true]))
  end

  it "counts a pending recheck as work left" do
    backlog = described_class.new([])
    backlog.requeue(9)
    expect(backlog.pending?).to(be(true))
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
    described_class.new(queue).take(worker(fresh: false))
    expect(queue).to(eq([1, 2]))
  end
end
