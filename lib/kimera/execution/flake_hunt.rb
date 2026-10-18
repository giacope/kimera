# frozen_string_literal: true

require_relative "suite_env"
require_relative "flake_record"
require_relative "worker_pool"

class Kimera::Execution::FlakeHunt
  RANGE = 2**31

  def initialize(adapter, driver, progress, env: ENV)
    @adapter = adapter
    @driver = driver
    @progress = progress
    @env = env
  end

  def call(coverage, scope, settings)
    seeds = series(settings[:seed], Integer(settings[:flaky_runs] || 0))
    return if seeds.empty?
    hunt(@adapter.test_ids & (scope ? coverage.slice(*scope) : coverage).values.flatten, seeds).tap do |record|
      settings[:filter]&.flag!(record.flaky)
    end
  end

  private

  def hunt(tests, seeds)
    saved = @env[Kimera::Execution::SEED_ENV]
    Kimera::Execution::FlakeRecord.new(tests, seeds).tap do |record|
      seeds.each.with_index(1) { |seed, round| sweep(tests, seed, record, "flaky check #{round}/#{seeds.size}") }
    end
  ensure
    saved ? @env.store(Kimera::Execution::SEED_ENV, saved) : @env.delete(Kimera::Execution::SEED_ENV)
  end

  def series(seed, runs) = Array.new(runs) { |index| seed ? (seed + index + 1) % RANGE : Random.new_seed % RANGE }

  def sweep(tests, seed, record, label)
    @env[Kimera::Execution::SEED_ENV] = seed.to_s
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
