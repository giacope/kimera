# frozen_string_literal: true

require_relative "parallel_databases"

class Kimera::Execution::NumberedDatabases
  def initialize(errors: $stderr, env: ENV)
    @errors = errors
    @env = env
  end

  def numbered? = renamed(number(1)).any?

  def prepare(index)
    renamed(number(index)).each do |config|
      ActiveRecord::Tasks::DatabaseTasks.reconstruct_from_schema(config)
    end
  rescue StandardError => error
    @errors.puts("kimera: could not create the database for worker #{index} (#{error.class}: #{error.message})")
  end

  def adopt(index)
    number = number(index)
    return if renamed(number).empty?
    ActiveRecord::Base.configurations = numbered(number) { configurations }
    ActiveRecord::Base.establish_connection
  end

  private

  def renamed(number)
    numbered(number) { configurations }.configs_for(env_name: environment).reject { |config| same?(config) }
  rescue StandardError
    []
  end

  def configurations = ActiveRecord::DatabaseConfigurations.new(Rails.application.config.database_configuration)

  def number(index) = Kimera::Execution::ParallelDatabases.new(env: @env).numbered(index).values.first

  def numbered(number, env = @env)
    variable = Kimera::Execution::ParallelDatabases::VARIABLE
    saved = env.fetch(variable, nil)
    env.store(variable, number)
    yield
  ensure
    saved ? env.store(variable, saved) : env.delete(variable)
  end

  def same?(config)
    ActiveRecord::Base.configurations.configs_for(env_name: environment, name: config.name)&.database == config.database
  end

  def environment = ActiveRecord::ConnectionHandling::DEFAULT_ENV.call
end
