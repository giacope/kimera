# frozen_string_literal: true

require "json"
require "tempfile"
require "kimera/execution/shift"
require "kimera/execution/worker_pool"
require_relative "property_helper"

# Fault injection for the real pool, with scripts drawn from the child
# actions in formal/WorkerPool.tla. The real parent (WorkerPool, Fleet,
# Worker, StillbornGuard) drives forked children that follow a random script,
# either speaking Shift's pipe protocol themselves or running the real Shift
# over an adapter that injects the faults, and the run must keep the model's
# safety invariants. Every run's steps are also logged
# (support/pool_trace.rb), and the second property has TLC check that each
# log is a behavior of the model, step by step (support/trace_check.rb,
# formal/WorkerPoolTrace.tla).
#
# Each mutant's script is [warm, recheck]: what its child does when offered
# it warm, and again on a fresh worker after a requeue. A scripted recheck
# never requeues (Attempt#recheck settles on a Doubt); under Shift it may
# try, and Shift must rule a harness_error instead. Every run is supervised in
# its own process group with a deadline of its own, so a pool that stops
# polling fails the example instead of hanging the suite.
RSpec.describe(Kimera::Execution::WorkerPool) do
  let(:warm) { Pbt.one_of(:result, :result, :result, :leak, :tainted, :requeue, :requeue, :crash, :hang, :partial) }
  let(:recheck) { Pbt.one_of(:result, :leak, :tainted, :crash, :hang, :partial) }
  let(:scripts) { Pbt.array(Pbt.tuple(warm, recheck), min: 1, max: 6) }
  # Fleet#take with its sources swapped: a fresh worker serves the queue
  # before a recheck. Every verdict is still right and every recheck still
  # runs on a fresh worker, so only the trace shows the change.
  let(:mutant) do
    Module.new do
      def take(worker) = following || (worker.fresh? && rechecks.shift)
    end
  end

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

  # The verdict a result carries.
  def status(behavior) = behavior == :tainted ? "timeout" : "killed"

  def report(behavior, id, response)
    say(response, t: "result", id: id, status: status(behavior), ms: 1, fails: [])
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

  # Runs inside the supervisor: the pool, a log of what it reported, and its
  # trace. A mutant module, if given, is prepended to Fleet first.
  def run(script, jobs, log, mutant)
    Kimera::Execution::WorkerPool::Fleet.prepend(mutant) if mutant
    tally = { events: [], slots: [], error: nil }
    PoolTrace.record((1..script.size).to_a, jobs) { judge(tally, script, jobs, log) }
    tally
  end

  def judge(tally, script, jobs, log)
    pool(tally, spawner(tally, script, jobs, log), script.size, jobs).run
  rescue Kimera::Error => error
    tally[:error] = error.message
  ensure
    tally[:trace] = PoolTrace.recorder.to_h
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
      tally[:events] << [kind.to_sym, message["id"], message["status"]] if %w[result requeue].include?(kind)
    end
  end

  def supervised(script, jobs, mutant: nil)
    Tempfile.create("offers") do |log|
      tally = Supervised.run(deadline: deadline) { run(script, jobs, log.path, mutant) }
      raise(Kimera::Error, "the supervised run raised #{tally.detail}") if tally.is_a?(Supervised::Crashed)
      tally.merge(offers: File.readlines(log.path).map(&:split))
    end
  end

  def outcome(behavior) = { crash: :crash, hang: :timeout, partial: :timeout }.fetch(behavior, :result)

  # What each mutant's last child does with it.
  def final(script) = script.map { |warm, recheck| warm == :requeue ? recheck : warm }

  # What each mutant ends with, given its script.
  def expected(script) = final(script).each_with_index.map { |behavior, index| [index + 1, outcome(behavior)] }

  def statuses(events) = events.filter_map { |kind, id, status| [id, status] if kind == :result }

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

  def judged(tally, script, jobs)
    safe(tally, script)
    if tally[:error]
      expect(tally[:error]).to(include("died before reporting a result"))
      expect(stillborn?(tally, script, jobs)).to(be(true), "aborted though StillbornGuard's condition did not hold")
    else
      expect(verdicts(tally[:events])).to(match_array(expected(script)))
      expect(requeues(tally[:events])).to(match_array(requeued(script)))
    end
  end

  # Safety holds whether or not the run completed.
  def safe(tally, script)
    judged = verdicts(tally[:events])
    expect(tally[:slots]).to(be_empty, "a slot was out of range or still held")
    expect(judged).to(all(satisfy { expected(script).include?(it) }))
    expect(judged.map(&:first)).to(eq(judged.map(&:first).uniq), "a mutant got two verdicts")
    expect(statuses(tally[:events])).to(all(satisfy { |id, status| status == status(final(script)[id - 1]) }))
    requeues = requeues(tally[:events])
    expect(requeues).to(eq(requeues.uniq).and(all(satisfy { requeued(script).include?(it) })))
    expect(tally[:offers]).not_to(include([anything, "true", "false"]), "a recheck reached a used worker")
  end

  def conforming(runs)
    skip("trace validation runs TLC, which needs Java") unless TraceCheck.available?
    TraceCheck.new(runs).verdict
  end

  # The trace is checked once all runs are in: one TLC run per pool size.
  shared_examples("a pool the model describes") do
    it "gives each mutant the one verdict its script calls for, and steps as formal/WorkerPool.tla does" do
      runs = []
      for_all(scripts, Pbt.integer(min: 1, max: 3), runs: 30) do |script, jobs|
        tally = supervised(script, jobs)
        runs << [jobs, tally[:trace]]
        judged(tally, script, jobs)
      end
      accepted, report = conforming(runs)
      expect(accepted).to(be(true), "a run is not a behavior of the model:\n#{report}")
    end
  end

  it_behaves_like("a pool the model describes")

  it "rejects the trace of a parent that serves the queue before a recheck", :aggregate_failures do
    script = [%i[requeue result], %i[result result]]
    tally = supervised(script, 1, mutant: mutant)
    safe(tally, script)
    expect(verdicts(tally[:events])).to(match_array(expected(script)))
    accepted, report = conforming([[1, tally[:trace]]])
    expect([accepted, report[/REJECTED at step \d+/]]).to(eq([false, "REJECTED at step 5"]))
  end

  it "times out a worker that flushes half a line and hangs with its pipe open" do
    tally = supervised([%i[partial result], %i[result result]], 1)
    expect([tally[:error], verdicts(tally[:events])]).to(eq([nil, [[1, :timeout], [2, :result]]]))
  end

  # The real Shift in each child, with an adapter that injects the faults
  # (support/faulty_adapter.rb). Shift decides what goes down the pipe, so
  # the child side of the protocol is the code's, not a script's.
  context("with Shift as the child") do
    let(:warm) { Pbt.one_of(:killed, :killed, :survived, :leak, :tainted, :requeue, :requeue, :crash, :hang) }
    let(:recheck) { Pbt.one_of(:killed, :survived, :leak, :tainted, :requeue, :crash, :hang) }

    # Room for a Trial and a LeakGuard re-run under a loaded machine: a slow
    # healthy child would get the wrong verdict.
    def soft = 0.25

    def watchdog = 1.0

    # A recheck that stays in doubt is ruled harness_error; it never requeues.
    def status(behavior)
      { killed: "killed", leak: "killed", survived: "survived", tainted: "timeout", requeue: "harness_error" }
        .fetch(behavior)
    end

    def child(script, log)
      forked do |request, response|
        offers = OfferTap.new(request, log)
        shift(script, offers).serve(offers, response)
        exit!(0)
      end
    end

    def shift(script, offers)
      Kimera::Execution::Shift.new(
        adapter: FaultyAdapter.new(script, offers), registry: Struct.new(:index).new({}),
        coverage: (1..script.size).to_h { [it, ["t"]] }, soft_timeout: soft, leak_every: 1
      )
    end

    it_behaves_like("a pool the model describes")
  end
end
