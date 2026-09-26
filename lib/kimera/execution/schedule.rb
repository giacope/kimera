# frozen_string_literal: true

require_relative "priority"
require_relative "reload"
require_relative "verdicts"

class Kimera::Execution::Schedule
  Ledger = Struct.new(:results, :leaks)
  Batch = Struct.new(:safe, :reloadable, :deferred, :ledger)

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
    Batch.new(Kimera::Execution::Priority.new(coverage).order(safe), reloadable, deferred, Ledger.new({}, []))
  end

  def process(batch)
    safe, reloadable, deferred, ledger = batch.to_a
    pool(safe, ledger)
    reload(reloadable, ledger)
    defer(deferred, ledger)
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

  def reload(ids, ledger)
    ids.each { |id| record(ledger, id, reloader.run(id, deadline: hard)) }
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
    ->(id, reason) { record(ledger, id, lost(id, reason)) }
  end

  def resolve(message, ledger)
    case message["t"]
    when "result" then parse(message, ledger)
    when "leak" then ledger.leaks << Kimera::LeakReport.new(mutant_id: message["id"], detail: message["detail"])
    end
  end

  def parse(message, ledger)
    result = verdicts.parse(message)
    record(ledger, result.mutant_id, result)
  end

  def lost(id, reason) = __send__(LOSSES.fetch(reason, :crashed), id)

  def expired(id) = verdicts.timeout(id, hard)

  def crashed(id) = verdicts.unjudged(id, "worker crashed before result")

  def reloader
    Kimera::Execution::Reload.new(
      registry: @registry, adapter: @options.fetch(:adapter),
      isolation: @options.fetch(:isolation), root: @options.fetch(:root)
    )
  end
end
