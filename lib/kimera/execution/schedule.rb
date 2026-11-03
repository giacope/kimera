# frozen_string_literal: true

require_relative "priority"
require_relative "kinship"
require_relative "reload"
require_relative "verdicts"

class Kimera::Execution::Schedule
  Ledger = Struct.new(:results, :leaks)
  Batch = Struct.new(:safe, :reloadable, :deferred, :ledger, :coverage)

  LOSSES = { timeout: :expired }.freeze

  def initialize(registry:, driver:, spawner:, **options)
    @registry = registry
    @driver = driver
    @spawner = spawner
    @options = options
  end

  def run(ids, coverage:, label: "mutants")
    kept, settled = screened(coverage)
    progress.during(ids.size, label) do |tick|
      batch = plan(ids - settled.keys, kept)
      settled.slice(*ids).each { |id, result| record(batch.ledger, id, result, tick) }
      process(batch, tick)
      finish(batch.ledger)
    end
  end

  private

  def progress = @options.fetch(:progress)

  def filters = Array(@options[:filter])

  def screened(coverage)
    active = filters.select(&:active?)
    return [coverage, {}] if active.empty?
    active.fetch(0).screen(coverage).tap { |kept, _settled| @driver.narrow(kept) }
  end

  def hard = @options.fetch(:hard)

  def verdicts = @_verdicts ||= @options.fetch(:verdicts) { Kimera::Execution::Verdicts.new(@registry) }

  def plan(ids, coverage, ledger = Ledger.new({}, []))
    safe, reloadable, deferred = verdicts.tiers(ids)
    Batch.new(prioritized(safe, coverage), reloadable, deferred, ledger, coverage)
  end

  def prioritized(safe, coverage) = Kimera::Execution::Priority.new(coverage).order(safe)

  def process(batch, tick)
    ledger = batch.ledger
    pool(batch.safe, ledger, tick)
    reload(batch, tick)
    defer(batch.deferred, ledger, tick)
  end

  def finish(ledger)
    results = verdicts.reclassified(ledger.results).values
    Kimera::RunReport.new(results: results, leaks: ledger.leaks, registry: @registry)
  end

  def record(ledger, id, result, tick)
    ledger.results[id] = result
    tick.call(result.status)
  end

  def reload(batch, tick)
    kinship = Kimera::Execution::Kinship.new(@registry, batch.coverage)
    batch.reloadable.each { |id| record(batch.ledger, id, rerun(id, kinship), tick) }
  end

  def rerun(id, kinship)
    tests = kinship.order(id, @options.fetch(:adapter).test_ids)
    filters.map { |filter| settled(filter, id, tests) }.fetch(0) { reloader.run(id, deadline: hard, tests: tests) }
  end

  def settled(filter, id, tests)
    filter.settle(id, tests) || reloader.run(id, deadline: hard, tests: filter.keep(verdicts.path(id), tests))
  end

  def defer(ids, ledger, tick)
    ids.each { |id| record(ledger, id, verdicts.quarantine(id), tick) }
  end

  def pool(queue, ledger, tick)
    listeners = Kimera::Execution::WorkerPool::Listeners.new(
      resolve: ->(message) { resolve(message, ledger, tick) },
      lost: ->(id, reason, stacks) { record(ledger, id, lost(id, reason, stacks), tick) }, trace: nil
    )
    @driver.drive(queue, @spawner, listeners)
  end

  def resolve(message, ledger, tick)
    case message["t"]
    when "result" then parse(message, ledger, tick)
    when "leak", "requeue" then ledger.leaks << Kimera::LeakReport.new(
      mutant_id: message["id"],
      detail: message["detail"]
    )
    end
  end

  def parse(message, ledger, tick)
    result = verdicts.parse(message).tap { |parsed| parsed.killing_tests = message["kills"] }
    record(ledger, result.mutant_id, result, tick)
  end

  def lost(id, reason, stacks) = __send__(LOSSES.fetch(reason, :crashed), id, stacks)

  def expired(id, stacks) = verdicts.timeout(id, hard, stacks)

  def crashed(id, obituary) = verdicts.unjudged(id, ["worker crashed before result", *obituary].join(": "))

  def reloader = @_reloader ||= @options.fetch(:reloader) { reloading }

  def reloading
    Kimera::Execution::Reload.new(
      registry: @registry, adapter: @options.fetch(:adapter), isolation: @options.fetch(:isolation),
      workspace: Kimera::Execution::Reload::Workspace.new(root: @options.fetch(:root), aliases: @options[:aliases])
    )
  end
end
