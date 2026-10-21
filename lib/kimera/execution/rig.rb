# frozen_string_literal: true

require_relative "flake_hunt"
require_relative "worker_databases"
require_relative "pool_driver"
require_relative "schedule"

class Kimera::Execution::Rig
  def initialize(**options)
    @options = options
  end

  def driver = @_driver ||= pool

  def spawner = @_spawner ||= @options[:spawner] || driver.method(:worker)

  def schedule = @_schedule ||= plan

  def hunt(coverage, scope, settings)
    Kimera::Execution::FlakeHunt.new(@options.fetch(:adapter), driver, @options.fetch(:progress))
      .call(coverage, scope, settings)
  end

  private

  def parallel
    @_parallel ||= Kimera::Execution::WorkerDatabases.new(jobs: @options.fetch(:jobs))
  end

  def pool
    Kimera::Execution::Pool.new(
      adapter: @options.fetch(:adapter), registry: @options.fetch(:registry),
      isolation: @options.fetch(:isolation), jobs: @options.fetch(:jobs), hard: @options.fetch(:hard),
      soft: @options.fetch(:soft), paralleldb: parallel, coverage: @options[:coverage],
      quality: @options[:test_quality], confirm: @options[:confirm_survivors]
    )
  end

  def plan
    Kimera::Execution::Schedule.new(
      registry: @options.fetch(:registry), driver: driver, spawner: spawner,
      adapter: @options.fetch(:adapter), isolation: @options.fetch(:isolation),
      root: @options.fetch(:root), progress: @options.fetch(:progress), hard: @options.fetch(:hard),
      aliases: @options[:aliases], filter: @options[:filter]
    )
  end
end
