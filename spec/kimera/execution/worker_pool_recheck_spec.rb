# frozen_string_literal: true

require "json"
require "kimera/execution/worker_pool"
require "timeout"

# A worker whose kill didn't reproduce asks for a recheck: the pool retires it
# and hands the mutant to a worker that has run nothing yet.
RSpec.describe(Kimera::Execution::WorkerPool) do
  def pool(queue:, spawner:, jobs: 1, deadline: 5.0)
    resolved = []
    lost = []
    resolve = ->(message) { resolved << message }
    loss = ->(id, reason, stacks) { lost << [id, reason, stacks] }
    options = { queue: queue, spawner: spawner, jobs: jobs, hard_timeout: deadline }
    described_class.new(resolve: resolve, lost: loss, **options).run
    [resolved, lost]
  end

  # Echoes each request in its result, so the parent sees what it sent.
  # +suspect+ ids get a requeue instead, and the worker stops serving.
  def echo(suspect: [])
    forked do |request, response|
      served = 0
      while (line = request.gets)
        ask = JSON.parse(line)
        break response.puts(JSON.generate(t: "requeue", id: ask["id"], detail: "suspect")) if doubt?(ask, suspect)
        served += 1
        report(response, ask, served)
      end
      response.puts(JSON.generate(t: "done"))
      exit!(0)
    end
  end

  def doubt?(ask, suspect) = suspect.include?(ask["id"]) && !ask["recheck"]

  def report(response, ask, served)
    result = { t: "result", id: ask["id"], status: "killed", recheck: ask["recheck"], pid: Process.pid }
    response.puts(JSON.generate(result.merge(served: served)))
    response.puts(JSON.generate(t: "ready"))
    response.flush
  end

  def results(resolved) = resolved.select { |message| message["t"] == "result" }

  def result(resolved, id) = results(resolved).find { |message| message["id"] == id }

  it "rechecks a suspect kill on a fresh worker and retires the worker that asked", :aggregate_failures do
    resolved, lost = Timeout.timeout(10) { pool(queue: [1, 2, 3], spawner: ->(_slot) { echo(suspect: [2]) }) }

    expect(lost).to(be_empty)
    expect(resolved.find { |message| message["t"] == "requeue" }).to(include("id" => 2, "detail" => "suspect"))
    expect(result(resolved, 2)).to(include("recheck" => true, "served" => 1))
    expect(result(resolved, 2)["pid"]).not_to(eq(result(resolved, 1)["pid"]))
    expect(results(resolved).map { |message| message["id"] }).to(contain_exactly(1, 2, 3))
    expect([1, 3].map { |id| result(resolved, id)["recheck"] }).to(eq([nil, nil]))
  end

  it "spawns a fresh worker for a recheck even when the queue is empty" do
    resolved, = Timeout.timeout(10) { pool(queue: [1], spawner: ->(_slot) { echo(suspect: [1]) }) }
    expect(results(resolved)).to(contain_exactly(include("id" => 1, "recheck" => true, "served" => 1)))
  end

  it "keeps a recheck from a worker that has already served a mutant", :aggregate_failures do
    spawned = 0
    spawner = ->(_slot) { echo(suspect: [1]).tap { spawned += 1 } }
    resolved, = Timeout.timeout(10) { pool(queue: [1, 2, 3, 4], spawner: spawner, jobs: 2) }

    expect(result(resolved, 1)).to(include("recheck" => true, "served" => 1))
    expect(spawned).to(eq(3))
  end

  it "hands a timed-out worker's stacks to the loss" do
    stacks = Object.new
    stacks.define_singleton_method(:take) { |pid| "stacks of #{pid}" }
    worker = nil
    spawner = ->(_slot) { worker = forked { sleep(30) }.push(stacks) }

    _, lost = Timeout.timeout(10) { pool(queue: [1], spawner: spawner, deadline: 0.3) }
    expect(lost).to(eq([[1, :timeout, "stacks of #{worker.first}"]]))
  end

  it "loses a crash with how the worker died, never its stacks, even from an armed worker" do
    stacks = Object.new
    stacks.define_singleton_method(:take) { |_pid| raise(ArgumentError, "a crash is never dumped") }

    _, lost = pool(queue: [1], spawner: ->(_slot) { forked { exit!(1) }.push(stacks) })
    expect(lost).to(eq([[1, :crash, "exited 1"]]))
  ensure
    Process.waitall
  end
end
