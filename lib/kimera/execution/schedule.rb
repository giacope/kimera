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
    batch = plan(ids, coverage, label)
    process(batch)
    finish(batch.ledger)
  ensure
    progress.finish
  end

  private

  def progress = @options.fetch(:progress)

  def hard = @options[:hard]

  def verdicts = @_verdicts ||= Kimera::Execution::Verdicts.new(@registry)

  def plan(ids, coverage, label)
    safe, unsafe = ids.partition { |id| verdicts.safe?(id) }
    reloadable, deferred = unsafe.partition { |id| verdicts.reloadable?(id) }
    progress.start(safe.size + unsafe.size, label)
    Batch.new(prioritized(safe, coverage), reloadable, deferred, Ledger.new({}, []), coverage)
  end

  def prioritized(safe, coverage) = Kimera::Execution::Priority.new(coverage).order(safe)

  def process(batch)
    ledger = batch.ledger
    pool(batch.safe, ledger)
    reload(batch)
    defer(batch.deferred, ledger)
  end

  def finish(ledger)
    results = ledger.results
    verdicts.reclassify!(results)
    Kimera::RunReport.new(results: results.values, leaks: ledger.leaks, registry: @registry)
  end

  def record(ledger, id, result)
    ledger.results[id] = result
    progress.tick(result.status)
  end

  def reload(batch)
    kinship = Kimera::Execution::Kinship.new(@registry, batch.coverage)
    batch.reloadable.each { |id| record(batch.ledger, id, rerun(id, kinship)) }
  end

  def rerun(id, kinship)
    reloader.run(id, deadline: hard, tests: kinship.order(id, @options.fetch(:adapter).test_ids))
  end

  def defer(ids, ledger)
    ids.each { |id| record(ledger, id, verdicts.quarantine(id)) }
  end

  def pool(queue, ledger)
    @driver.drive(queue, @spawner, resolve: resolver(ledger), lost: loser(ledger))
  end

  def resolver(ledger)
    ->(message) { resolve(message, ledger) }
  end

  def loser(ledger)
    ->(id, reason, stacks) { record(ledger, id, lost(id, reason, stacks)) }
  end

  def resolve(message, ledger)
    case message["t"]
    when "result" then parse(message, ledger)
    when "leak", "requeue" then ledger.leaks << Kimera::LeakReport.new(
      mutant_id: message["id"],
      detail: message["detail"]
    )
    end
  end

  def parse(message, ledger)
    result = verdicts.parse(message)
    record(ledger, result.mutant_id, result)
  end

  def lost(id, reason, stacks) = __send__(LOSSES.fetch(reason, :crashed), id, stacks)

  def expired(id, stacks) = verdicts.timeout(id, hard, stacks)

  def crashed(id, _stacks) = verdicts.unjudged(id, "worker crashed before result")

  def reloader
    @_reloader ||= Kimera::Execution::Reload.new(
      registry: @registry, adapter: @options.fetch(:adapter),
      isolation: @options.fetch(:isolation), root: @options.fetch(:root)
    )
  end
end
