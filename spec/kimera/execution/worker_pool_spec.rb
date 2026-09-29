# frozen_string_literal: true

require "json"
require "kimera/execution/worker_pool"
require "timeout"

# Failure handling only; happy paths are covered in harness_spec.
RSpec.describe(Kimera::Execution::WorkerPool) do
  def pool(queue:, spawner:, jobs: 1, deadline: 5.0)
    resolved = []
    lost = []
    described_class.new(
      queue: queue, spawner: spawner, jobs: jobs, hard_timeout: deadline,
      resolve: lambda do |message|
        resolved << message
      end, lost: lambda do |id, reason, _stacks|
        lost << [id, reason]
      end
    ).run
    [resolved, lost]
  end

  # +settling+ simulates the post-result leak-check re-run.
  def healthy(preamble: [], evaluation: 0, settling: 0)
    forked do |request, response|
      while (line = request.gets)
        id = JSON.parse(line)["id"]
        preamble.each { |line| response.puts(line) }
        response.puts(JSON.generate(t: "start", id: id))
        sleep(evaluation) if evaluation.positive?
        response.puts(JSON.generate(t: "result", id: id, status: "killed", ms: 1, fails: []))
        response.flush
        sleep(settling) if settling.positive?
        response.puts(JSON.generate(t: "ready"))
        response.flush
      end
      response.puts(JSON.generate(t: "done"))
      response.close
      exit!(0)
    end
  end

  def crashed
    forked do |_request, _response|
      exit!(1)
    end
  end

  def blocked
    forked do |_request, _response|
      sleep(30)
      exit!(0)
    end
  end

  def single
    forked do |request, response|
      if (line = request.gets)
        id = JSON.parse(line)["id"]
        response.puts(JSON.generate(t: "start", id: id))
        response.puts(JSON.generate(t: "result", id: id, status: "killed", ms: 1, fails: []))
        response.puts(JSON.generate(t: "ready"))
        response.flush
      end
      request.gets # die with the next dispatch in flight
      exit!(1)
    end
  end

  # Serves until retired, then hangs in teardown (a truncate blocked by a leaked lock).
  def stuck
    forked do |request, response|
      while (line = request.gets)
        id = JSON.parse(line)["id"]
        response.puts(JSON.generate(t: "result", id: id, status: "killed", ms: 1, fails: []))
        response.puts(JSON.generate(t: "ready"))
        response.flush
      end
      sleep(30)
      exit!(0)
    end
  end

  def signal
    lambda do |_slot|
      forked do |_request, _response|
        Process.kill("KILL", Process.pid)
      end
    end
  end

  def rotation(threshold: 2)
    calls = 0
    lambda do |_slot|
      calls += 1
      calls <= threshold ? single : healthy
    end
  end

  def recovery
    calls = 0
    lambda do |_slot|
      calls += 1
      calls == 1 ? single : healthy
    end
  end

  def watchdog
    calls = 0
    lambda do |_slot|
      calls += 1
      calls == 1 ? blocked : healthy
    end
  end

  def slots
    slots = []
    calls = 0
    [
      slots,
      lambda do |slot|
        slots << slot
        calls += 1
        calls == 1 ? single : healthy
      end
    ]
  end

  def leak
    counter = [0]
    [
      counter,
      lambda do |_slot|
        counter[0] += 1
        healthy(evaluation: 0.4, settling: 0.8)
      end
    ]
  end

  # Ticks before each covering test, then reports after longer than the deadline.
  def ticking
    forked do |request, response|
      while (line = request.gets)
        id = JSON.parse(line)["id"]
        4.times do
          response.puts(JSON.generate(t: "tick"))
          response.flush
          sleep(0.2)
        end
        response.puts(JSON.generate(t: "result", id: id, status: "survived", ms: 1, fails: []))
        response.puts(JSON.generate(t: "ready"))
        response.flush
      end
      exit!(0)
    end
  end

  # The hard timeout times each covering test, so a mutant many tests cover
  # isn't killed for that alone.
  it "renews a worker's hard deadline on every tick", :aggregate_failures do
    resolved, lost = pool(queue: [1], spawner: ->(_slot) { ticking }, deadline: 0.5)
    expect(lost).to(be_empty)
    expect(resolved.map { |message| message["status"] }).to(eq(["survived"]))
  end

  it "aborts once more workers than the pool is wide die without reporting" do
    # The exit description is the operator's only clue before retrying with --jobs 1.
    expect { pool(queue: (1..6).to_a, spawner: ->(_slot) { crashed }, jobs: 2) }
      .to(raise_error(Kimera::Error, /3 warm workers died before reporting.*last exit: status 1/m))
  ensure
    # abort_pool! leaves dead workers unreaped; reap so later ECHILD probes stay meaningful.
    Process.waitall
  end

  it "describes a signal death distinctly in the abort message" do
    expect { pool(queue: (1..6).to_a, spawner: signal, jobs: 2) }.to(raise_error(Kimera::Error, /last exit: signal 9/))
  ensure
    Process.waitall
  end

  # A hang is the mutant's fault; only crashes are systemic.
  it "does not trip the circuit breaker on repeated timeouts" do
    lost = nil
    Timeout.timeout(15) do
      _, lost = pool(queue: [1, 2, 3], spawner: ->(_slot) { blocked }, deadline: 0.3)
    end
    expect(lost).to(eq([[1, :timeout], [2, :timeout], [3, :timeout]]))
  end

  it "keeps going through repeated crashes once the pool has made progress", :aggregate_failures do
    resolved, lost = pool(queue: (1..6).to_a, spawner: rotation, jobs: 1)
    judged = resolved.select { |m| m["t"] == "result" }.map { |m| m["id"] }

    # Two deaths exceed jobs, which would trip the breaker without prior progress.
    expect(lost.map(&:last)).to(eq(%i[crash crash]))
    expect(judged.size).to(eq(4))
    expect(judged + lost.map(&:first)).to(match_array((1..6).to_a))
  end

  it "never dispatches a duplicate queue entry that already resolved", :aggregate_failures do
    resolved, lost = pool(queue: [1, 1, 2], spawner: ->(_slot) { healthy })

    expect(lost).to(be_empty)
    expect(resolved.select { |m| m["t"] == "result" }.map { |m| m["id"] }).to(eq([1, 2]))
  end

  it "never re-dispatches a duplicate of a crashed id", :aggregate_failures do
    resolved, lost = pool(queue: [1, 2, 2, 3], spawner: recovery)

    # Worker one resolves 1, then dies holding 2.
    expect(lost).to(eq([[2, :crash]]))
    expect(resolved.select { |m| m["t"] == "result" }.map { |m| m["id"] }).to(eq([1, 3]))
  end

  it "tolerates a garbage line on the result pipe", :aggregate_failures do
    resolved, lost = pool(queue: [1, 2], spawner: ->(_slot) { healthy(preamble: ["!!not json!!"]) })

    expect(lost).to(be_empty)
    expect(resolved.select { |m| m["t"] == "result" }.map { |m| m["id"] }).to(contain_exactly(1, 2))
  end

  it "watchdogs a worker that wedges before its first message", :aggregate_failures do
    resolved = lost = nil
    spawner = watchdog
    Timeout.timeout(10) { resolved, lost = pool(queue: [1, 2], spawner: spawner, deadline: 0.3) }

    # Only the pre-start deadline can retire a worker that never speaks.
    expect(lost).to(eq([[1, :timeout]]))
    expect(resolved.select { |m| m["t"] == "result" }.map { |m| m["id"] }).to(eq([2]))
  end

  # A readable pipe need not hold a whole line: blocking on the rest of it
  # would stall the loop before its watchdog ever ran.
  def halting(*writes, linger: 30)
    forked do |request, response|
      request.gets
      writes.each do |text|
        response.write(text)
        response.flush
        sleep(0.05)
      end
      sleep(linger)
      exit!(0)
    end
  end

  def result(id) = JSON.generate(t: "result", id: id, status: "killed", ms: 1, fails: [])

  it "watchdogs a worker that writes half a line and hangs", :aggregate_failures do
    resolved = lost = nil
    spawner = ->(_slot) { halting('{"t":"res') }
    Timeout.timeout(10) { resolved, lost = pool(queue: [1], spawner: spawner, deadline: 0.3) }

    expect(lost).to(eq([[1, :timeout]]))
    expect(resolved).to(be_empty)
  end

  it "joins a line split across writes and splits lines that share one", :aggregate_failures do
    line = result(1)
    spawner = ->(_slot) { halting(line[0, 9], "#{line[9..]}\n#{JSON.generate(t: "leak", id: 1)}\n", linger: 0) }
    resolved, lost = pool(queue: [1], spawner: spawner)

    expect(resolved.map { |m| m["t"] }).to(eq(%w[result leak]))
    expect(lost).to(be_empty)
  end

  # IO.select can report a pipe ready with nothing to read yet.
  def spurious(response)
    woken = false
    read = response.method(:read_nonblock)
    allow(response).to(receive(:read_nonblock)) do |*args, **options|
      next read.call(*args, **options) if woken
      woken = true
      :wait_readable
    end
  end

  it "waits out a spurious wakeup instead of reading it as data", :aggregate_failures do
    spawner = ->(_slot) { healthy.tap { |_pid, _request, response| spurious(response) } }
    resolved, lost = pool(queue: [1], spawner: spawner)

    expect(resolved.select { |m| m["t"] == "result" }.map { |m| m["id"] }).to(eq([1]))
    expect(lost).to(be_empty)
  end

  it "reads a last line the worker wrote without a newline before it exited", :aggregate_failures do
    resolved, lost = pool(queue: [1], spawner: ->(_slot) { halting(result(1), linger: 0) })

    expect(resolved.map { |m| m["id"] }).to(eq([1]))
    expect(lost).to(be_empty)
  end

  it "kills a retired worker whose teardown hangs, so the run still ends", :aggregate_failures do
    resolved = lost = nil
    Timeout.timeout(10) { resolved, lost = pool(queue: [1, 2], spawner: ->(_slot) { stuck }, deadline: 0.5) }

    # Nothing was in flight, so nothing is charged to a mutant.
    expect(lost).to(be_empty)
    expect(resolved.select { |m| m["t"] == "result" }.map { |m| m["id"] }).to(eq([1, 2]))
  end

  it "returns a crashed worker's slot to its replacement" do
    slots, spawner = self.slots
    pool(queue: [1, 2, 3], spawner: spawner, jobs: 1)

    # A nil slot would cost the replacement its own test database.
    expect(slots).to(eq([0, 0]))
  end

  it "closes both parent pipe ends when a worker crashes" do
    pipes = []
    spawner =
      lambda do |_slot|
        crashed.tap { |connection| pipes.concat(connection.drop(1)) }
      end

    pool(queue: [1], spawner: spawner)
    expect(pipes).to(all(be_closed))
  ensure
    pipes&.each { |pipe| pipe.close unless pipe.closed? }
  end

  it "extends the deadline through the post-result leak-check", :aggregate_failures do
    counter, spawner = leak
    _, lost = pool(queue: [1, 2], spawner: spawner, deadline: 1.0)

    # 0.4s eval + 0.8s settle exceeds the 1.0s deadline unless it re-arms on result.
    expect(lost).to(be_empty)
    expect(counter[0]).to(eq(1))
  end
end
