# frozen_string_literal: true

require "json"
require "tempfile"
require "kimera/execution/shift"
require "kimera/execution/worker_pool"
require_relative "../../property_helper"

RSpec.describe(Kimera::Execution::WorkerPool) do
  let(:behaviors) { Pbt.one_of(:result, :result, :result, :tainted, :crash, :hang, :partial) }
  let(:scripts) { Pbt.array(behaviors, min: 1, max: 6) }
  let(:mutant) do
    Module.new do
      def take = queue.pop
    end
  end

  def watchdog = 0.4

  def deadline = 15

  def founded(grandchildren)
    forked do |request, response|
      Process.setpgid(0, 0)
      grandchildren.spawn
      yield(request, response)
    end
  end

  def child(script, log, grandchildren)
    founded(grandchildren) do |request, response|
      while (line = request.gets)
        id = JSON.parse(line)["id"]
        File.write(log, "#{id}\n", mode: "a")
        act(script.fetch(id - 1), id, response)
      end
      say(response, t: "done")
      exit!(0)
    end
  end

  def act(behavior, id, response)
    case behavior
    when :crash then exit!(1)
    when :hang then sleep(60)
    when :partial then halt(response, JSON.generate(t: "result", id: id)[0, 12])
    else report(behavior, id, response)
    end
  end

  def halt(response, text)
    response.write(text)
    response.flush
    sleep(60)
  end

  def status(behavior) = behavior == :tainted ? "timeout" : "killed"

  def report(behavior, id, response)
    say(response, t: "result", id: id, status: status(behavior), ms: 1, fails: [])
    say(response, t: "ready")
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

  def run(script, jobs, log, mutant)
    Kimera::Execution::WorkerPool::Backlog.prepend(mutant) if mutant
    grandchildren = witness
    tally = { events: [], slots: [], error: nil, grandchildren: grandchildren }
    PoolTrace.record((1..script.size).to_a, jobs) { judge(tally, script, jobs, log) }
    tally.except(:grandchildren).merge(outlived: grandchildren.outlived?)
  end

  def judge(tally, script, jobs, log)
    pool(tally, spawner(tally, script, jobs, log), script.size, jobs).run
  rescue Kimera::Error => error
    tally[:error] = error.message
  ensure
    tally[:trace] = PoolTrace.recorder.to_h
  end

  def spawner(tally, script, jobs, log)
    holders = {}
    lambda do |slot|
      holder = holders[slot]
      tally[:slots] << slot unless (0...jobs).cover?(slot) && !(holder && alive?(holder))
      child(script, log, tally[:grandchildren]).tap { |pid, *| holders[slot] = pid }
    end
  end

  def pool(tally, spawner, size, jobs)
    lost = ->(id, reason, _stacks) { tally[:events] << [:lost, id, reason] }
    listeners = described_class::Listeners.new(resolve: resolver(tally), lost: lost, trace: nil)
    options = { jobs: jobs, hard_timeout: watchdog }
    described_class.new((1..size).to_a, spawner, listeners, options)
  end

  def resolver(tally)
    lambda do |message|
      tally[:events] << [:result, message["id"], message["status"]] if message["t"] == "result"
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

  def expected(script) = script.each_with_index.map { |behavior, index| [index + 1, outcome(behavior)] }

  def statuses(events) = events.filter_map { |kind, id, status| [id, status] if kind == :result }

  def verdicts(events) = events.map { |kind, id, reason| [id, kind == :lost ? reason : :result] }

  def stillborn?(tally, script, jobs)
    events = tally[:events]
    crashes = tally[:offers].count { |(id)| script[Integer(id) - 1] == :crash }
    events.none? { it.first == :result } && events.count { it.last == :crash } == jobs && crashes > jobs
  end

  def judged(tally, script, jobs)
    safe(tally, script)
    tally[:error] ? aborted(tally, script, jobs) : completed(tally[:events], script)
  end

  def aborted(tally, script, jobs)
    expect(tally[:error]).to(include("died before reporting a result"))
    expect(stillborn?(tally, script, jobs)).to(be(true), "aborted though StillbornGuard's condition did not hold")
  end

  def completed(events, script) = expect(verdicts(events)).to(match_array(expected(script)))

  def safe(tally, script)
    released(tally)
    once(tally[:events], script)
  end

  def released(tally)
    expect(tally[:slots]).to(be_empty, "a slot was out of range or still held")
    expect(tally[:outlived]).to(be(false), "a process a worker started outlived the run")
  end

  def once(events, script)
    judged = verdicts(events)
    ids = judged.map(&:first)
    facts = {
      unscripted: judged - expected(script), repeated: ids.size - ids.uniq.size, unfinished: unfinished(events, script)
    }
    expect(facts).to(eq(unscripted: [], repeated: 0, unfinished: []))
  end

  def unfinished(events, script) = statuses(events).reject { |id, status| status == status(script[id - 1]) }

  def conforming(runs)
    skip("trace validation runs TLC, which needs Java") unless TraceCheck.available?
    TraceCheck.new(runs).verdict
  end

  shared_examples("a pool the model describes") do
    def scripted_runs
      runs = []
      for_all(scripts, Pbt.integer(min: 1, max: 3), runs: 30) do |script, jobs|
        tally = supervised(script, jobs)
        runs << [jobs, tally[:trace]]
        judged(tally, script, jobs)
      end
      runs
    end

    it "gives each mutant the one verdict its script calls for, and steps as formal/WorkerPool.tla does" do
      accepted, report = conforming(scripted_runs)
      expect(accepted).to(be(true), "a run is not a behavior of the model:\n#{report}")
    end
  end

  it_behaves_like("a pool the model describes")

  it "rejects the trace of a parent that serves the queue from its tail", :aggregate_failures do
    script = %i[result result]
    tally = supervised(script, 1, mutant: mutant)
    safe(tally, script)
    expect(verdicts(tally[:events])).to(match_array(expected(script)))
    expect(conforming([[1, tally[:trace]]]).then { |accepted, report| [accepted, report[/REJECTED at step \d+/]] })
      .to(eq([false, "REJECTED at step 1"]))
  end

  it "times out a worker that flushes half a line and hangs with its pipe open" do
    tally = supervised(%i[partial result], 1)
    expect([tally[:error], verdicts(tally[:events])]).to(eq([nil, [[1, :timeout], [2, :result]]]))
  end

  context("with Shift as the child") do
    let(:behaviors) { Pbt.one_of(:killed, :killed, :survived, :fading, :tainted, :suspect, :crash, :hang) }

    def soft = 0.25

    def watchdog = 1.0

    def status(behavior)
      { killed: "killed", fading: "killed", survived: "survived", tainted: "timeout", suspect: "killed" }
        .fetch(behavior)
    end

    def child(script, log, grandchildren)
      founded(grandchildren) do |request, response|
        offers = OfferTap.new(request, log)
        shift(script, offers).serve(offers, response)
        exit!(0)
      rescue Kimera::Execution::Zygote::Died => error
        Kimera::Execution::Pool::Duty.new.echo(error)
      end
    end

    def shift(script, offers)
      Kimera::Execution::Shift.new(
        adapter: FaultySuite.new(script, offers), registry: Kimera::Registry.new,
        coverage: (1..script.size).to_h { [it, ["t"]] }, soft_timeout: soft
      )
    end

    it_behaves_like("a pool the model describes")
  end
end
