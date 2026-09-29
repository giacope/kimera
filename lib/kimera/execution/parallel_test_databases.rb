# frozen_string_literal: true

class Kimera::Execution::ParallelTestDatabases
  LOCK_WAITS = { /postg/i => "SET lock_timeout = '5s'", /mysql|trilogy/i => "SET SESSION lock_wait_timeout = 5" }.freeze

  def initialize(adapter:, jobs:, errors: nil)
    @adapter = adapter
    @jobs = jobs
    @errors = errors
  end

  def active?
    return false unless eligible?
    register!
    ActiveSupport::Testing::Parallelization.after_fork_hooks.any?
  end

  def before_fork
    return unless active?
    ActiveSupport::Testing::Parallelization.before_fork_hooks.each(&:call)
  end

  def after_fork(index)
    identify(index)
    return unless index && active?
    ActiveSupport::Testing::Parallelization.after_fork_hooks.each { |hook| hook.call(index) }
    @adapter.start
  end

  def before_exit(index)
    attempt("parallelize_teardown failed") { Array(index).each { |worker| cleanup(worker) } }
  end

  private

  def cleanup(index)
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
    configured?
  end

  def configured?
    ActiveSupport.parallelize_test_databases
  rescue NoMethodError
    false
  end

  def register!
    return unless defined?(ActiveRecord::Base)
    require("active_record/test_databases")
  rescue LoadError, StandardError => error
    errors.puts(notice(error))
  end

  def notice(error)
    "kimera: per-worker test databases unavailable (#{error.class}: #{error.message}); workers share one database"
  end
end
