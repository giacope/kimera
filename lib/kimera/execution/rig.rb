# frozen_string_literal: true

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

  private

  def parallel
    @_parallel ||= Kimera::Execution::WorkerDatabases.new(
      adapter: @options.fetch(:adapter), jobs: @options.fetch(:jobs)
    )
  end

  def pool
    Kimera::Execution::Pool.new(
      adapter: @options.fetch(:adapter), registry: @options.fetch(:registry),
      isolation: @options.fetch(:isolation), jobs: @options.fetch(:jobs), hard: @options.fetch(:hard),
      soft: @options.fetch(:soft), leak: @options.fetch(:leak), paralleldb: parallel, coverage: @options[:coverage]
    )
  end

  def plan
    Kimera::Execution::Schedule.new(
      registry: @options.fetch(:registry), driver: driver, spawner: spawner,
      adapter: @options.fetch(:adapter), isolation: @options.fetch(:isolation),
      root: @options.fetch(:root), progress: @options.fetch(:progress), hard: @options.fetch(:hard),
      aliases: @options[:aliases]
    )
  end
end
