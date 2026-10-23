# frozen_string_literal: true

module Kimera
  module Execution
  end
end

# Which database each warm worker and isolated mirror gets. Rails 8.1 added
# ActiveSupport.parallelize_test_databases; before it, the after-fork hook
# active_record/test_databases registers gave each parallel worker its own
# database whenever it was registered. TEST_ENV_NUMBER follows parallel_tests:
# the first process keeps the plain name, the nth appends n. A schema path
# Active Record cannot work out (a suite without Rails has no db_dir) is no
# schema to load: the worker copies the database instead.
class Kimera::Execution::ParallelDatabases
  VARIABLE = "TEST_ENV_NUMBER"

  def initialize(
    env: ENV, support: (ActiveSupport if defined?(ActiveSupport)),
    record: (ActiveRecord::Base if defined?(ActiveRecord::Base))
  )
    @env = env
    @support = support
    @record = record
  end

  def enabled?
    return true unless @support.respond_to?(:parallelize_test_databases)
    @support.parallelize_test_databases
  end

  def loadable?
    return true unless @record
    configs = @record.configurations.configs_for(env_name: ActiveRecord::ConnectionHandling::DEFAULT_ENV.call)
    configs.all? { |config| File.exist?(ActiveRecord::Tasks::DatabaseTasks.schema_dump_path(config)) }
  rescue StandardError
    false
  end

  def numbered(index) = { VARIABLE => number(index) }

  def assign(index, env = @env) = env.update(numbered(index))

  private

  def number(index) = index.zero? ? "" : (index + 1).to_s
end
