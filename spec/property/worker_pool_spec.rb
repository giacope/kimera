# frozen_string_literal: true

require "json"
require "tempfile"
require "kimera/execution/worker_pool"
require_relative "property_helper"

# Fault injection for the real pool, with scripts drawn from the child
# actions in formal/WorkerPool.tla. The real parent (WorkerPool, Fleet,
# Worker, StillbornGuard) drives forked children that follow a random script
# instead of running Shift, and the run must keep the model's safety
# invariants. This does not replay TLC traces or check that each real step
# is one of the model's transitions.
#
# Each mutant's script is [warm, recheck]: what its child does when offered
# it warm, and again on a fresh worker after a requeue. A recheck never
# requeues (Attempt#recheck settles on a Doubt). Every run is supervised in
# its own process group with a deadline of its own, so a pool that stops
# polling fails the example instead of hanging the suite.
RSpec.describe(Kimera::Execution::WorkerPool) do
  let(:warm) { Pbt.one_of(:result, :result, :result, :leak, :tainted, :requeue, :requeue, :crash, :hang, :partial) }
  let(:recheck) { Pbt.one_of(:result, :leak, :tainted, :crash, :hang, :partial) }
  let(:scripts) { Pbt.array(Pbt.tuple(warm, recheck), min: 1, max: 6) }

  def watchdog = 0.4

  # Twice the worst case (every mutant hangs on one worker) plus fork time.
  def deadline = 15

  # Logs one line per offer the child receives: "id recheck first?".
  def child(script, log)
    served = 0
    forked do |request, response|
      while (line = request.gets)
        offer = JSON.parse(line)
        id = offer["id"]
        File.write(log, "#{id} #{offer.fetch("recheck", false)} #{served.zero?}\n", mode: "a")
        served += 1
        break unless act(script.fetch(id - 1)[offer["recheck"] ? 1 : 0], id, response)
      end
      say(response, t: "done")
      exit!(0)
    end
  end

  # Shift#step and Shift#process, reduced to their pipe traffic.
  def act(behavior, id, response)
    case behavior
    when :crash then exit!(1)
    when :hang then sleep(60)
    when :partial then halt(response, JSON.generate(t: "result", id: id)[0, 12])
    when :requeue then say(response, t: "requeue", id: id, detail: "suspect")
    else report(behavior, id, response)
    end
  end

  # Half a line, flushed, then silence with the pipe held open.
  def halt(response, text)
    response.write(text)
    response.flush
    sleep(60)
  end

  def report(behavior, id, response)
    say(response, t: "result", id: id, status: behavior == :tainted ? "timeout" : "killed", ms: 1, fails: [])
    say(response, t: "leak", id: id, detail: "leak") if behavior == :leak
    say(response, t: "ready") unless behavior == :tainted
  end

  def say(io, **message)
    io.puts(JSON.generate(message))
    io.flush
  end

  def alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  end

  # Runs inside the supervisor: the pool, and a log of what it reported.
  def run(script, jobs, log)
    tally = { events: [], slots: [], error: nil }
    pool(tally, spawner(tally, script, jobs, log), script.size, jobs).run
    tally
  rescue Kimera::Error => error
    tally.merge(error: error.message)
  end

  # A slot is reused only once its last holder is reaped.
  def spawner(tally, script, jobs, log)
    holders = {}
    lambda do |slot|
      holder = holders[slot]
      tally[:slots] << slot unless (0...jobs).cover?(slot) && !(holder && alive?(holder))
      child(script, log).tap { |pid, *| holders[slot] = pid }
    end
  end

  def pool(tally, spawner, size, jobs)
    lost = ->(id, reason, _stacks) { tally[:events] << [:lost, id, reason] }
    described_class.new(
      queue: (1..size).to_a, spawner: spawner, jobs: jobs, hard_timeout: watchdog, resolve: resolver(tally), lost: lost
    )
  end

  def resolver(tally)
    lambda do |message|
      kind = message["t"]
      tally[:events] << [kind.to_sym, message["id"]] if %w[result requeue].include?(kind)
    end
  end

  def supervised(script, jobs)
    Tempfile.create("offers") do |log|
      tally = Supervised.run(deadline: deadline) { run(script, jobs, log.path) }
      raise(Kimera::Error, "the supervised run raised #{tally.detail}") if tally.is_a?(Supervised::Crashed)
      tally.merge(offers: File.readlines(log.path).map(&:split))
    end
  end

  def outcome(behavior) = { crash: :crash, hang: :timeout, partial: :timeout }.fetch(behavior, :result)

  # What each mutant ends with, given its script.
  def expected(script)
    script.each_with_index.map { |(warm, recheck), index| [index + 1, outcome(warm == :requeue ? recheck : warm)] }
  end

  def verdicts(events)
    events.filter_map { |kind, id, reason| [id, kind == :lost ? reason : :result] unless kind == :requeue }
  end

  def requeues(events) = events.filter_map { |kind, id| id if kind == :requeue }

  def requeued(script) = script.each_index.select { |i| script[i][0] == :requeue }.map { it + 1 }

  # StillbornGuard may abort only before any result, on the crash after
  # `jobs` recorded ones (it raises before recording that one).
  def stillborn?(tally, script, jobs)
    events = tally[:events]
    crashes = tally[:offers].count { |id, recheck| script[Integer(id) - 1][recheck == "true" ? 1 : 0] == :crash }
    events.none? { it.first == :result } && events.count { it.last == :crash } == jobs && crashes > jobs
  end

  # Safety holds whether or not the run completed.
  def safe(tally, script)
    judged = verdicts(tally[:events])
    expect(tally[:slots]).to(be_empty, "a slot was out of range or still held")
    expect(judged).to(all(satisfy { expected(script).include?(it) }))
    expect(judged.map(&:first)).to(eq(judged.map(&:first).uniq), "a mutant got two verdicts")
    requeues = requeues(tally[:events])
    expect(requeues).to(eq(requeues.uniq).and(all(satisfy { requeued(script).include?(it) })))
    expect(tally[:offers]).not_to(include([anything, "true", "false"]), "a recheck reached a used worker")
  end

  it "gives every mutant exactly the one verdict its script calls for, or aborts only when it must" do
    for_all(scripts, Pbt.integer(min: 1, max: 3), runs: 30) do |script, jobs|
      tally = supervised(script, jobs)
      safe(tally, script)
      if tally[:error]
        expect(tally[:error]).to(include("died before reporting a result"))
        expect(stillborn?(tally, script, jobs)).to(be(true), "aborted though StillbornGuard's condition did not hold")
      else
        expect(verdicts(tally[:events])).to(match_array(expected(script)))
        expect(requeues(tally[:events])).to(match_array(requeued(script)))
      end
    end
  end

  it "times out a worker that flushes half a line and hangs with its pipe open" do
    tally = supervised([%i[partial result], %i[result result]], 1)
    expect([tally[:error], verdicts(tally[:events])]).to(eq([nil, [[1, :timeout], [2, :result]]]))
  end
end
