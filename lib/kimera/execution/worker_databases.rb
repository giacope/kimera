# frozen_string_literal: true

require_relative "memory_databases"
require_relative "numbered_databases"
require_relative "parallel_databases"
require_relative "parent_connections"

# Gives each warm worker its own test database. The parent loaded the suite
# and ran its suite hooks once; a worker runs Rails' parallel after-fork hooks
# only, as Rails' own parallel workers do, never the suite's hooks again.
class Kimera::Execution::WorkerDatabases
  LOCK_WAITS = { /postg/i => "SET lock_timeout = '5s'", /mysql|trilogy/i => "SET SESSION lock_wait_timeout = 5" }.freeze
  SHARED = "kimera: the %d workers share one test database (%s): Active Record is loaded, but neither Rails' " \
    "parallel test databases nor a TEST_ENV_NUMBER in database.yml give each worker its own; tests that " \
    "write the same rows can fail or pass by timing (use jobs: 1, or name the database per worker)"

  def initialize(jobs:, errors: nil, env: ENV)
    @jobs = jobs
    @errors = errors
    @env = env
  end

  def active? = eligible? && parallel.enabled? && hooks.any?

  def before_fork
    register!
    Kimera::Execution::ParentConnections.new.release!
    return before_hooks.each(&:call) if active?
    prepare
  end

  def after_fork(index)
    identify(index)
    return unless index && @jobs > 1
    parallel.assign(index)
    register!
    return numbered.adopt(index) unless active?
    hooks.each { |hook| hook.call(index) }
  end

  def before_exit(index)
    attempt("parallelize_teardown failed") { Array(index).each { |worker| cleanup(worker) } }
  end

  private

  def hooks = ActiveSupport::Testing::Parallelization.after_fork_hooks

  def before_hooks
    ActiveSupport::Testing::Parallelization.before_fork_hooks
  rescue NoMethodError
    []
  end

  def cleanup(index)
    register!
    return unless active?
    attempt("could not empty the worker's test database") { scrub }
    ActiveSupport::Testing::Parallelization.run_cleanup_hooks.each { |hook| hook.call(index) }
  end

  def identify(index)
    return unless index && @jobs > 1 && defined?(ActiveSupport::TestCase)
    ActiveSupport::TestCase.parallel_worker_id = index
  rescue NoMethodError
    nil
  end

  def numbered = @_numbered ||= Kimera::Execution::NumberedDatabases.new(errors: errors, env: @env)

  def parallel = Kimera::Execution::ParallelDatabases.new(env: @env)

  def memory? = Kimera::Execution::MemoryDatabases.new.current?

  def prepare
    return if @_prepared || !separate?
    @_prepared = true
    return (1...@jobs).each { |index| numbered.prepare(index) } if numbered.numbered?
    shared
  end

  def separate? = @jobs > 1 && defined?(ActiveRecord::Base) && !memory?

  def shared
    errors.puts(format(SHARED, @jobs, ActiveRecord::Base.connection_db_config.database))
  rescue StandardError
    nil
  end

  def attempt(failure)
    yield
  rescue StandardError => error
    errors.puts("kimera: #{failure} (#{error.class}: #{error.message})")
  end

  def scrub
    return unless defined?(ActiveRecord::Base)
    connection = ActiveRecord::Base.connection
    bound(connection)
    connection.truncate_tables(*connection.tables)
  end

  def bound(connection)
    statement = LOCK_WAITS.find { |pattern, _| connection.adapter_name.match?(pattern) }&.last
    connection.execute(statement) if statement
  end

  def errors = @errors || $stderr

  def eligible?
    return false unless @jobs > 1
    return false unless defined?(ActiveSupport::Testing::Parallelization)
    !memory?
  end

  def register!
    return unless eligible? && defined?(ActiveRecord::Base) && parallel.enabled?
    require("active_record/test_databases")
  rescue LoadError, StandardError => error
    errors.puts(notice(error))
  end

  def notice(error)
    "kimera: per-worker test databases unavailable (#{error.class}: #{error.message}); workers share one database"
  end
end
