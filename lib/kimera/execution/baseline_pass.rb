# frozen_string_literal: true

require "stringio"
require_relative "../error"
require_relative "../runtime"
require_relative "baseline_failure"
require_relative "baseline_losses"
require_relative "baseline_order"
require_relative "baseline_screen"
require_relative "baseline_tally"
require_relative "worker_pool"
require_relative "null_progress"
require_relative "zygote"
require_relative "standard_streams"

class Kimera::Execution::BaselinePass
  EVERY = :itself.to_proc

  def initialize(adapter:, registry:, **options)
    @adapter = adapter
    @registry = registry
    @options = options
  end

  def parallel!(jobs, &)
    progress.start(tests.size, "baseline")
    settle(jobs) { dispatch(&) }
  end

  def check!(cell = zygote)
    outcome = sequence(cell)
    return if outcome["passed"]
    red!(outcome["failed_ids"], 1, outcome["failures"]) { [] }
  end

  def sequence(cell = zygote) = cell.call { whole }

  def alone?(test) = Kimera::RUNTIME.during(nil) { quietly { @adapter.run([test]) } }.passed?

  private

  def progress = @options.fetch(:progress) { Kimera::Execution::NullProgress.new }

  def zygote = @options.fetch(:zygote) { Kimera::Execution::Zygote.new }

  def roots = Array(@options[:root])

  def settle(jobs)
    yield
    failures = tally.failures
    red!(failures, jobs) { ordered(failures) } unless failures.empty?
    tally.measured(losses.recovered(tally.messages))
  ensure
    progress.finish
  end

  def ordered(failures) = Kimera::Execution::BaselineOrder.new(self).of(failures, zygote) { [] }

  def tests = @_tests ||= @options.fetch(:measured, EVERY).call(@adapter.test_ids)

  def tally
    @_tally ||= @options.fetch(:tally) { Kimera::Execution::BaselineTally.new(Hash.new { |h, k| h[k] = [] }, [], [], {}, {}) }
  end

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
    yield(tests, nil, listeners(method(:lost), ->(slot, test_id) { journal[slot] << test_id }))
    stalled = losses.stalled
    yield(stalled, 1, listeners(method(:relapse), nil)) unless stalled.empty?
  end

  def listeners(lost, trace) = Kimera::Execution::WorkerPool::Listeners.new(resolve: resolve, lost: lost, trace: trace)

  def losses = @_losses ||= @options.fetch(:losses) { Kimera::Execution::BaselineLosses.new }

  def journal = @_journal ||= Hash.new { |workers, slot| workers[slot] = [] }

  def resolve = ->(message) { receive(message) }

  def receive(message)
    touched = message["touched"]
    test_id = message["id"]
    tally.cover(test_id, touched, message["took"])
    bank(test_id, touched, message: message["failure"]) unless message["passed"]
    progress.tick
  end

  def lost(test_id, reason, stacks = nil)
    return losses.stall(test_id, stacks) if reason == :timeout
    relapse(test_id, reason, stacks)
  end

  def relapse(test_id, reason, stacks = nil)
    tally.messages[test_id] = losses.charge(test_id, reason, stacks)
    tally.failures << test_id
    progress.tick
  end

  def bank(test_id, touched, message: nil)
    tally.messages[test_id] = message
    bucket(touched) << test_id
  end

  def bucket(touched)
    Array(touched).any? { |id| @registry.index.key?(id) } ? tally.failures : tally.irrelevant
  end

  def red!(failed, jobs, messages = tally.messages)
    roots.each { |root| screen(jobs, root).plainly!(failed.to_h { |id| [id, losses.told(id, messages[id])] }) }
    failure!(failed, jobs, yield, messages: messages)
  end

  def screen(jobs, root) = screens.new(adapter: @adapter, root: root, jobs: jobs)

  def screens = @options.fetch(:screens, Kimera::Execution::BaselineScreen)

  def quietly(streams = Kimera::Execution::StandardStreams.new, &) = streams.quietly(&)

  def failure!(failed, jobs, ordered = [], messages: tally.messages)
    summary = Kimera::Execution::BaselineFailure::Summary
    command = @adapter.reproduce(failed.first(summary::MAX_DETAILS))
    context = summary::Context.new(workers: journal, stacks: losses.stacks, jobs: jobs, ordered: ordered)
    raise(Kimera::Execution::BaselineFailure, summary.new(failed, messages, command, context).to_s)
  end
end
