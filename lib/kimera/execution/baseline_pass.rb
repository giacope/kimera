# frozen_string_literal: true

require "stringio"
require_relative "../error"
require_relative "../runtime"
require_relative "baseline_failure"
require_relative "baseline_losses"
require_relative "baseline_order"
require_relative "baseline_tally"
require_relative "worker_pool"
require_relative "null_progress"
require_relative "zygote"

class Kimera::Execution::BaselinePass
  def initialize(adapter:, registry:, progress: Kimera::Execution::NullProgress::NONE)
    @adapter = adapter
    @registry = registry
    @progress = progress
  end

  def parallel!(jobs, &) = settle(jobs) { dispatch(&) }

  def check!(zygote = Kimera::Execution::Zygote.new)
    outcome = sequence(zygote)
    return if outcome["passed"]
    failure!(outcome["failed_ids"], 1, messages: outcome["failures"])
  end

  def sequence(zygote = Kimera::Execution::Zygote.new) = zygote.call { whole }

  def alone?(test)
    Kimera::RUNTIME.active = nil
    quietly { @adapter.run([test]) }.passed?
  end

  private

  def settle(jobs)
    yield
    failures = tally.failures
    failure!(failures, jobs, Kimera::Execution::BaselineOrder.new(self).of(failures)) unless failures.empty?
    tally.measured(losses.recovered(tally.messages))
  ensure
    @progress.finish
  end

  def tally = @_tally ||= Kimera::Execution::BaselineTally.new(Hash.new { |h, k| h[k] = [] }, [], [], {}, {})

  def whole
    Kimera::RUNTIME.active = nil
    ledger = Kimera::RUNTIME.start!
    summary(quietly { @adapter.run(@adapter.test_ids) }).merge("touched" => ledger.drain!)
  ensure
    Kimera::RUNTIME.stop!(ledger)
  end

  def summary(outcome)
    { "passed" => outcome.passed?, "failed_ids" => outcome.failed_ids, "failures" => outcome.failures }
  end

  def dispatch
    tests = @adapter.test_ids
    @progress.start(tests.size, "baseline")
    yield(tests, nil, listeners(method(:lost), ->(slot, test_id) { journal[slot] << test_id }))
    stalled = losses.stalled
    yield(stalled, 1, listeners(method(:relapse), nil)) unless stalled.empty?
  end

  def listeners(lost, trace) = Kimera::Execution::WorkerPool::Listeners.new(resolve: resolve, lost: lost, trace: trace)

  def losses = @_losses ||= Kimera::Execution::BaselineLosses.new

  def journal = @_journal ||= Hash.new { |workers, slot| workers[slot] = [] }

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
    tally.messages[test_id] = losses.charge(test_id, reason, stacks)
    tally.failures << test_id
    @progress.tick
  end

  def bank(test_id, touched, message: nil)
    tally.messages[test_id] = message
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

  def failure!(failed, jobs, ordered = [], messages: tally.messages)
    summary = Kimera::Execution::BaselineFailure::Summary
    command = @adapter.reproduce(failed.first(summary::MAX_DETAILS))
    context = summary::Context.new(workers: journal, stacks: losses.stacks, jobs: jobs, ordered: ordered)
    raise(Kimera::Execution::BaselineFailure, summary.new(failed, messages, command, context).to_s)
  end
end
