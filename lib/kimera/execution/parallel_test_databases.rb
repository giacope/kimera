# frozen_string_literal: true

class Kimera::Execution::ParallelTestDatabases
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
    return unless index && active?
    ActiveSupport::Testing::Parallelization.after_fork_hooks.each { |hook| hook.call(index) }
    @adapter.start
  end

  def before_exit(index)
    Array(index).each { cleanup }
  rescue StandardError => error
    errors.puts("kimera: parallelize_teardown failed (#{error.class}: #{error.message})")
  end

  private

  def cleanup
    return unless active?
    scrub
    ActiveSupport::Testing::Parallelization.run_cleanup_hooks.each(&:call)
  end

  def scrub
    return unless defined?(ActiveRecord::Base)
    connection = ActiveRecord::Base.connection
    connection.truncate_tables(*connection.tables)
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
