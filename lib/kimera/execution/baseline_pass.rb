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
    progress.during(tests.size, "baseline") { |tick| settle(jobs) { dispatch(tick, &) } }
  end

  def check!(cell = zygote)
    outcome = sequence(cell)
    return if outcome["passed"]
    red!(outcome["failed_ids"], 1, outcome["failures"]) { [] }
  end

  def sequence(cell = zygote) = cell.call { whole }

  def alone?(test, runtime = Kimera::RUNTIME) = runtime.during(nil) { quietly { @adapter.run([test]) } }.passed?

  private

  def progress = @options.fetch(:progress) { Kimera::Execution::NullProgress.new }

  def zygote = @options.fetch(:zygote) { Kimera::Execution::Zygote.new }

  def roots = Array(@options[:root])

  def settle(jobs)
    yield
    failures = tally.failures
    red!(failures, jobs) { ordered(failures) } unless failures.empty?
    tally.measured(losses.recovered(tally.messages))
  end

  def ordered(failures) = Kimera::Execution::BaselineOrder.new(self).of(failures, zygote) { [] }

  def tests = @_tests ||= @options.fetch(:measured, EVERY).call(@adapter.test_ids)

  def tally
    @_tally ||= @options.fetch(:tally) { Kimera::Execution::BaselineTally.new(Hash.new { |h, k| h[k] = [] }, [], [], {}, {}) }
  end

  def whole(runtime = Kimera::RUNTIME)
    ledger = Kimera::Runtime::Ledger.new
    outcome = runtime.during(nil, ledger) { quietly { @adapter.run(@adapter.test_ids) } }
    outcome.to_h.merge("touched" => ledger.drain!)
  end

  def dispatch(tick)
    yield(tests, nil, listeners(tick, ->(*loss) { lost(tick, *loss) }, ->(slot, test_id) { journal[slot] << test_id }))
    stalled = losses.stalled
    yield(stalled, 1, listeners(tick, ->(*loss) { relapse(tick, *loss) }, nil)) unless stalled.empty?
  end

  def listeners(tick, lost, trace)
    resolve = ->(message) { receive(message, tick) }
    Kimera::Execution::WorkerPool::Listeners.new(resolve: resolve, lost: lost, trace: trace)
  end

  def losses = @_losses ||= @options.fetch(:losses) { Kimera::Execution::BaselineLosses.new }

  def journal = @_journal ||= Hash.new { |workers, slot| workers[slot] = [] }

  def receive(message, tick)
    touched = message["touched"]
    test_id = message["id"]
    tally.cover(test_id, touched, message["took"])
    bank(test_id, touched, message: message["failure"]) unless message["passed"]
    tick.call
  end

  def lost(tick, test_id, reason, stacks = [])
    return losses.stall(test_id, stacks) if reason == :timeout
    relapse(tick, test_id, reason, stacks)
  end

  def relapse(tick, test_id, reason, stacks = [])
    tally.messages[test_id] = losses.charge(test_id, reason, stacks)
    tally.failures << test_id
    tick.call
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
    command = @adapter[*failed.first(summary::MAX_DETAILS)].to_s
    context = summary::Context.new(workers: journal, stacks: losses.stacks, jobs: jobs, ordered: ordered)
    raise(Kimera::Execution::BaselineFailure, summary.new(failed, messages, command, context).to_s)
  end
end
