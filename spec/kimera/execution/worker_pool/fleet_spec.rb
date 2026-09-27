# frozen_string_literal: true

require "kimera/execution/worker_pool"

RSpec.describe(Kimera::Execution::WorkerPool::Fleet) do
  def fleet(queue) = described_class.new(queue: queue, spawner: nil, jobs: 1, pool: nil)

  def worker(fresh:) = Struct.new(:fresh?).new(fresh)

  it "gives a recheck only to a worker that has run nothing yet", :aggregate_failures do
    fleet = fleet([1, 2])
    fleet.requeue(9)

    expect(fleet.take(worker(fresh: false))).to(eq(1))
    expect(fleet.take(worker(fresh: true))).to(eq(9))
    expect(fleet.take(worker(fresh: true))).to(eq(2))
  end

  it "remembers which ids are rechecks", :aggregate_failures do
    fleet = fleet([1])
    fleet.requeue(9)

    expect(fleet.recheck?(9)).to(be(true))
    expect(fleet.recheck?(1)).to(be(false))
  end

  it "counts a pending recheck as work left" do
    fleet = fleet([])
    fleet.requeue(9)
    expect(fleet.__send__(:pending?)).to(be(true))
  end

  it "has no work left once the queue holds only finished ids" do
    fleet = fleet([1])
    fleet.done!(1)
    expect(fleet.__send__(:pending?)).to(be(false))
  end
end
