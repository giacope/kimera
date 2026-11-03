# frozen_string_literal: true

require_relative "suite_env"
require_relative "flake_record"
require_relative "worker_pool"

class Kimera::Execution::FlakeHunt
  def initialize(adapter, driver, progress, env: ENV)
    @adapter = adapter
    @driver = driver
    @progress = progress
    @env = env
  end

  def call(coverage, scope, runs)
    seeds = runs.seeds
    return if seeds.empty?
    hunt(@adapter.test_ids & (scope ? coverage.slice(*scope) : coverage).values.flatten, seeds).tap do |record|
      runs.flag(record)
    end
  end

  private

  def hunt(tests, seeds, env = @env)
    Kimera::Execution::FlakeRecord.new(tests, seeds).tap do |record|
      seeds.each.with_index(1) do |seed, round|
        Kimera::Execution::SuiteEnv.new(env).seeded(seed) { sweep(tests, seed, record, "flaky check #{round}/#{seeds.size}") }
      end
    end
  end

  def sweep(tests, seed, record, label)
    @progress.during(tests.size, "#{label} (seed #{seed})") do |tick|
      listeners = Kimera::Execution::WorkerPool::Listeners.new(
        resolve: ->(message) { record.note(message, seed).then { tick.call } },
        lost: ->(test, reason, _stacks) { record.lose(test, reason, seed).then { tick.call } }, trace: nil
      )
      @driver.drive(tests, @driver.method(:channel), listeners)
    end
  end
end
