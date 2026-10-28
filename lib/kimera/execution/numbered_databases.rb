# frozen_string_literal: true

require_relative "env_patch"
require_relative "parallel_databases"
require_relative "tolerance"

class Kimera::Execution::NumberedDatabases
  def initialize(
    tolerance: Kimera::Execution::Tolerance.new($stderr), env: ENV, settings: -> { Rails.application.config }
  )
    @tolerance = tolerance
    @env = env
    @settings = settings
  end

  def numbered? = renamed(numbering(1)) { [] }.any?

  def prepare(index)
    @tolerance.attempt("could not create the database for worker #{index}") do
      renamed(numbering(index)) { [] }.each { |config| ActiveRecord::Tasks::DatabaseTasks.reconstruct_from_schema(config) }
    end
  end

  def adopt(index)
    numbering = numbering(index)
    return if renamed(numbering) { [] }.empty?
    ActiveRecord::Base.configurations = numbered(numbering) { configurations }
    ActiveRecord::Base.establish_connection
  end

  private

  def renamed(numbering)
    numbered(numbering) { configurations }.configs_for(env_name: environment).reject { |config| same?(config) }
  rescue StandardError
    yield
  end

  def configurations = ActiveRecord::DatabaseConfigurations.new(@settings.call.database_configuration)

  def numbering(index) = Kimera::Execution::ParallelDatabases.new(env: @env).numbered(index)

  def numbered(numbering, env = @env, &) = Kimera::Execution::EnvPatch.new(numbering).during(env, &)

  def same?(config)
    ActiveRecord::Base.configurations.configs_for(env_name: environment, name: config.name)&.database == config.database
  end

  def environment = ActiveRecord::ConnectionHandling::DEFAULT_ENV.call
end
