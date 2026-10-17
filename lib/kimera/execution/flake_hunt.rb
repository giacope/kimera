# frozen_string_literal: true

require_relative "flake_record"
require_relative "worker_pool"

class Kimera::Execution::FlakeHunt
  RANGE = 2**31

  def initialize(adapter, driver, progress)
    @adapter = adapter
    @driver = driver
    @progress = progress
  end

  def call(coverage, scope, settings)
    seeds = series(settings[:seed], Integer(settings[:flaky_runs] || 0))
    return if seeds.empty?
    record = hunt(@adapter.test_ids & (scope ? coverage.slice(*scope) : coverage).values.flatten, seeds)
    @adapter.seed = settings[:seed]
    settings[:filter]&.flag!(record)
  end

  private

  def hunt(tests, seeds)
    Kimera::Execution::FlakeRecord.new(tests, seeds).tap do |record|
      seeds.each.with_index(1) { |seed, round| sweep(tests, seed, record, "flaky check #{round}/#{seeds.size}") }
    end
  end

  def series(seed, runs) = Array.new(runs) { |index| seed ? (seed + index + 1) % RANGE : Random.new_seed % RANGE }

  def sweep(tests, seed, record, label)
    @adapter.seed = seed
    @progress.start(tests.size, "#{label} (seed #{seed})")
    listeners = Kimera::Execution::WorkerPool::Listeners.new(
      resolve: ->(message) { record.note(message, seed).then { @progress.tick } },
      lost: ->(test, reason, _stacks) { record.lose(test, reason, seed).then { @progress.tick } }, trace: nil
    )
    @driver.drive(tests, @driver.method(:channel), listeners)
  ensure
    @progress.finish
  end
end
