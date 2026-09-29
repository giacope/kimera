# frozen_string_literal: true

require "json"
require "tempfile"
require "kimera/execution/worker_pool"
require_relative "property_helper"

# The real pool against formal/WorkerPool.tla: forked children follow a
# random script drawn from the model's child actions, and the run must keep
# the model's invariants. Each mutant's script is [warm, recheck]: what its
# child does when offered it warm, and again on a fresh worker after a
# requeue. A recheck never requeues (Attempt#recheck settles on a Doubt).
RSpec.describe(Kimera::Execution::WorkerPool) do
  let(:warm) { Pbt.one_of(:result, :result, :result, :leak, :tainted, :requeue, :requeue, :crash, :hang) }
  let(:recheck) { Pbt.one_of(:result, :leak, :tainted, :crash, :hang) }
  let(:scripts) { Pbt.array(Pbt.tuple(warm, recheck), min: 1, max: 6) }

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
    when :hang then sleep(30)
    when :requeue then say(response, t: "requeue", id: id, detail: "suspect")
    else report(behavior, id, response)
    end
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

  # A slot may be reused only once its last holder is reaped.
  def alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  end

  def run(script, jobs, log)
    tally = { verdicts: [], requeues: [], holders: {}, children: [] }
    [tally, drive(pool(tally, spawner(tally, script, jobs, log), script.size, jobs))]
  ensure
    reap(tally[:children])
  end

  # An aborted run leaves its hung children behind; the pool reaped the rest.
  def reap(children)
    children.each do |pid|
      next if Process.wait(pid, Process::WNOHANG)
      Process.kill("KILL", pid)
      Process.wait(pid)
    rescue Errno::ECHILD
      nil
    end
  end

  def spawner(tally, script, jobs, log)
    lambda do |slot|
      holder = tally[:holders][slot]
      expect([slot, holder && alive?(holder)]).to(match([be_between(0, jobs - 1), be_falsey]))
      child(script, log).tap { |pid, *| tally[:children] << (tally[:holders][slot] = pid) }
    end
  end

  def pool(tally, spawner, size, jobs)
    lost = ->(id, reason, _stacks) { tally[:verdicts] << [id, reason] }
    described_class.new(
      queue: (1..size).to_a, spawner: spawner, jobs: jobs, hard_timeout: 0.4, resolve: resolver(tally), lost: lost
    )
  end

  def resolver(tally)
    lambda do |message|
      tally[:verdicts] << [message["id"], :result] if message["t"] == "result"
      tally[:requeues] << message["id"] if message["t"] == "requeue"
    end
  end

  def drive(pool)
    pool.run
    nil
  rescue Kimera::Error => error
    error
  end

  def verdict(behavior) = { crash: :crash, hang: :timeout }.fetch(behavior, :result)

  # What the model says each mutant ends with, given its script.
  def expected(script)
    script.each_with_index.map { |(warm, recheck), index| [index + 1, verdict(warm == :requeue ? recheck : warm)] }
  end

  def requeued(script) = script.each_index.select { |i| script[i][0] == :requeue }.map { it + 1 }

  it "gives every mutant exactly the one verdict its script calls for" do
    for_all(scripts, Pbt.integer(min: 1, max: 3), runs: 30) do |script, jobs|
      Tempfile.create("offers") do |log|
        tally, error = run(script, jobs, log.path)
        # StillbornGuard: more than `jobs` crashes before any result abort the run.
        next if error&.message&.include?("died before reporting a result")
        expect([error, tally[:verdicts]]).to(match([nil, match_array(expected(script))]))
        expect(tally[:requeues]).to(match_array(requeued(script)))
        expect(File.readlines(log.path).map(&:split)).not_to(include([anything, "true", "false"]))
      end
    end
  end
end
