# frozen_string_literal: true

require "stringio"
require_relative "../error"
require_relative "../runtime"
require_relative "baseline_failure"
require_relative "baseline_losses"
require_relative "baseline_tally"
require_relative "signal_guard"
require_relative "stopwatch"
require_relative "null_progress"

class Kimera::Execution::BaselinePass
  def initialize(adapter:, registry:, progress: Kimera::Execution::NullProgress)
    @adapter = adapter
    @registry = registry
    @progress = progress
    @messages = {}
  end

  def measure! = settle { serial }

  def parallel!(&) = settle { dispatch(&) }

  def check!
    Kimera::Runtime.active = nil
    outcome = quietly { @adapter.run(@adapter.test_ids) }
    return if outcome.passed?
    @messages = outcome.failures
    failure!(outcome.failed_ids)
  end

  private

  def settle
    @progress.start(@adapter.test_ids.size, "baseline")
    yield
    report
  ensure
    @progress.finish
  end

  def tally = @_tally ||= Kimera::Execution::BaselineTally.new(Hash.new { |h, k| h[k] = [] }, [], [], {})

  def report
    failures = tally.failures
    failure!(failures) unless failures.empty?
    tally.measured(excluded, losses.recovered(@messages))
  end

  def excluded = tally.irrelevant.to_h { |test_id| [test_id, @messages[test_id]] }

  def serial
    ledger = Kimera::Runtime.start!
    @adapter.test_ids.each { |test_id| attempt(ledger, test_id) }
  ensure
    Kimera::Runtime.stop!(ledger)
  end

  def attempt(ledger, test_id)
    Kimera::Runtime.active = nil
    Kimera::Runtime.clear!(ledger)
    watch = Kimera::Execution::Stopwatch.new
    record(test_id, watch.lap { sheltered(test_id) }, Kimera::Runtime.drain!(ledger), watch.last)
  end

  def sheltered(test_id) = Kimera::Execution::SignalGuard.run(test_id) { quietly { @adapter.run([test_id]) } }

  def record(test_id, outcome, touched, took)
    tally.cover(test_id, touched, took)
    bank(test_id, touched, message: outcome.failures[test_id]) unless outcome.passed?
    @progress.tick
  end

  def dispatch(&)
    yield(@adapter.test_ids, nil, resolve: resolve, lost: loss, trace: tracer)
    rerun(losses.stalled, &)
  end

  def rerun(ids)
    yield(ids, 1, resolve: resolve, lost: method(:relapse), trace: nil) unless ids.empty?
  end

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

  def loss = method(:lost)

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

  def failure!(failed)
    command = @adapter.reproduce(failed.first(Kimera::Execution::BaselineFailure::MAX_DETAILS))
    raise(Kimera::Execution::BaselineFailure.build(failed, @messages, command, workers: journal, stacks: losses.stacks))
  end
end
