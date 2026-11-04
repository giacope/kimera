# frozen_string_literal: true

require_relative "priority"
require_relative "kinship"
require_relative "reload"
require_relative "triage"
require_relative "verdicts"

class Kimera::Execution::Schedule
  Ledger =
    Struct.new(:results, :leaks) do
      private(*members)
      def record(id, result) = results.store(id, result)

      def leak(report) = leaks << report

      def report(triage, registry)
        Kimera::RunReport.new(results: triage.reclassified(results).values, leaks: leaks, registry: registry)
      end
    end

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
      tiers = plan(ids - settled.keys, kept)
      ledger = settle(settled.slice(*ids), tick)
      process(tiers, kept, ledger, tick)
      ledger.report(triage, @registry)
    end
  end

  private

  def progress = @options.fetch(:progress)

  def filters = Array(@options[:filter])

  def screened(coverage)
    filters.map { |filter| filter.screen(coverage) { |kept| @driver.narrow(kept) } }.fetch(0) { [coverage, {}] }
  end

  def hard = @options.fetch(:hard)

  def verdicts = @_verdicts ||= @options.fetch(:verdicts) { Kimera::Execution::Verdicts.new(@registry) }

  def triage = Kimera::Execution::Triage.new(verdicts)

  def plan(ids, coverage)
    safe, reloadable, deferred = triage.tiers(ids)
    [prioritized(safe, coverage), reloadable, deferred]
  end

  def settle(settled, tick, ledger = Ledger.new({}, []))
    ledger.tap { settled.each { |id, result| record(ledger, id, result, tick) } }
  end

  def prioritized(safe, coverage) = Kimera::Execution::Priority.new(coverage).order(safe)

  def process((safe, reloadable, deferred), coverage, ledger, tick)
    pool(safe, ledger, tick)
    reload(reloadable, coverage, ledger, tick)
    defer(deferred, ledger, tick)
  end

  def record(ledger, id, result, tick)
    ledger.record(id, result)
    tick.call(result.status)
  end

  def reload(ids, coverage, ledger, tick)
    kinship = Kimera::Execution::Kinship.new(@registry, coverage)
    ids.each { |id| record(ledger, id, rerun(id, kinship), tick) }
  end

  def rerun(id, kinship)
    tests = kinship.order(id, @options.fetch(:adapter).test_ids)
    filters.map { |filter| settled(filter, id, tests) }.fetch(0) { reloader.run(id, deadline: hard, tests: tests) }
  end

  def settled(filter, id, tests)
    filter.settle(id, tests) || reloader.run(id, deadline: hard, tests: filter.keep(verdicts.point(id).file, tests))
  end

  def defer(ids, ledger, tick)
    ids.each { |id| record(ledger, id, triage.quarantine(id), tick) }
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
    when "leak", "requeue" then ledger.leak(Kimera::LeakReport.new(mutant_id: message["id"], detail: message["detail"]))
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
