# frozen_string_literal: true

require "stringio"
require_relative "../error"
require_relative "../runtime"
require_relative "baseline_failure"
require_relative "baseline_losses"
require_relative "baseline_tally"
require_relative "signal_guard"
require_relative "stopwatch"
require_relative "worker_pool"
require_relative "null_progress"

class Kimera::Execution::BaselinePass
  def initialize(adapter:, registry:, progress: Kimera::Execution::NullProgress)
    @adapter = adapter
    @registry = registry
    @progress = progress
    @messages = {}
  end

  def measure! = settle(1) { serial }

  def parallel!(jobs, &) = settle(jobs) { dispatch(&) }

  def check!
    Kimera::RUNTIME.active = nil
    outcome = quietly { @adapter.run(@adapter.test_ids) }
    return if outcome.passed?
    @messages = outcome.failures
    failure!(outcome.failed_ids, 1)
  end

  private

  def settle(jobs)
    @progress.start(@adapter.test_ids.size, "baseline")
    yield
    report(jobs)
  ensure
    @progress.finish
  end

  def tally = @_tally ||= Kimera::Execution::BaselineTally.new(Hash.new { |h, k| h[k] = [] }, [], [], {})

  def report(jobs)
    failures = tally.failures
    failure!(failures, jobs) unless failures.empty?
    tally.measured(excluded, losses.recovered(@messages))
  end

  def excluded = tally.irrelevant.to_h { |test_id| [test_id, @messages[test_id]] }

  def serial
    ledger = Kimera::RUNTIME.start!
    @adapter.test_ids.each { |test_id| attempt(ledger, test_id) }
  ensure
    Kimera::RUNTIME.stop!(ledger)
  end

  def attempt(ledger, test_id)
    Kimera::RUNTIME.active = nil
    ledger.clear
    watch = Kimera::Execution::Stopwatch.new
    record(test_id, watch.lap { sheltered(test_id) }, ledger.drain!, watch.last)
  end

  def sheltered(test_id) = Kimera::Execution::SignalGuard.run(test_id) { quietly { @adapter.run([test_id]) } }

  def record(test_id, outcome, touched, took)
    tally.cover(test_id, touched, took)
    bank(test_id, touched, message: outcome.failures[test_id]) unless outcome.passed?
    @progress.tick
  end

  def dispatch(&)
    yield(@adapter.test_ids, nil, listeners(method(:lost), tracer))
    rerun(losses.stalled, &)
  end

  def rerun(ids)
    yield(ids, 1, listeners(method(:relapse), nil)) unless ids.empty?
  end

  def listeners(lost, trace) = Kimera::Execution::WorkerPool::Listeners.new(resolve: resolve, lost: lost, trace: trace)

  def losses = @_losses ||= Kimera::Execution::BaselineLosses.new

  def journal = @_journal ||= Hash.new { |workers, slot| workers[slot] = [] }

  def tracer = ->(slot, test_id) { journal[slot] << test_id }

  def resolve = ->(message) { receive(message) }

  def receive(message)
    touched = message["touched"]
    test_id = message["id"]
    tally.cover(test_id, touched, message["took"])
    bank(test_id, touched, message: message["failure"]) unless message["passed"]
    @progress.tick
  end

  def lost(test_id, reason, stacks = nil)
    return losses.stall(test_id, stacks) if reason == :timeout
    relapse(test_id, reason, stacks)
  end

  def relapse(test_id, reason, stacks = nil)
    @messages[test_id] = losses.charge(test_id, reason, stacks)
    tally.failures << test_id
    @progress.tick
  end

  def bank(test_id, touched, message: nil)
    @messages[test_id] = message
    bucket(touched) << test_id
  end

  def bucket(touched)
    Array(touched).any? { |id| @registry.index.key?(id) } ? tally.failures : tally.irrelevant
  end

  def quietly
    swap = [$stdout, $stderr]
    silence
    yield
  ensure
    $stdout, $stderr = swap
  end

  def silence
    $stdout = StringIO.new
    $stderr = StringIO.new
  end

  def failure!(failed, jobs)
    summary = Kimera::Execution::BaselineFailure::Summary
    command = @adapter.reproduce(failed.first(summary::MAX_DETAILS))
    context = summary::Context.new(workers: journal, stacks: losses.stacks, jobs: jobs)
    raise(Kimera::Execution::BaselineFailure, summary.new(failed, @messages, command, context).to_s)
  end
end
