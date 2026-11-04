# frozen_string_literal: true

require_relative "baseline_failure"
require_relative "isolation"
require_relative "memory_databases"

class Kimera::Execution::Boot
  def initialize(adapter:, isolate:, errors: $stderr)
    @adapter = adapter
    @isolate = isolate
    @errors = errors
  end

  def suite(test_files)
    @adapter.source(test_files)
    found!(test_files)
    @adapter.start
    load!
    keep!
  end

  def load!
    eager.each(&:eager_load!)
  rescue StandardError => error
    @errors.puts(failure(error))
  end

  def isolate(isolation)
    return isolation unless @isolate
    return isolation unless defined?(ActiveRecord::Base)
    Kimera::Execution::CompositeIsolation.new(
      [Kimera::Execution::TransactionIsolation.new(ActiveRecord::Base), isolation]
    )
  end

  private

  def found!(test_files)
    return if test_files.empty? || @adapter.test_ids.any?
    raise(
      Kimera::Execution::BaselineFailure,
      "baseline has no tests to run: #{test_files.size} test file(s) loaded but none of their tests is selected " \
        "(an inclusion filter such as RSpec's `filter_run_including focus: true` that matches nothing?); " \
        "kimera would score every mutant as uncovered"
    )
  end

  def keep!
    memory = Kimera::Execution::MemoryDatabases
    # rubocop:disable-next Kata/NoMonkeyPatch -- Active Record discards every pool a fork inherits, and a forked worker would lose the in-memory database the suite loaded its schema into; it has no setting to keep one
    ActiveRecord::ConnectionAdapters::PoolConfig.prepend(memory::INHERITED) if defined?(ActiveRecord::ConnectionAdapters::PoolConfig)
    # rubocop:disable-next Kata/NoMonkeyPatch -- sqlite3 >= 2 closes every writable handle a fork inherits, the in-memory schema with it, and offers no setting to spare one
    SQLite3::ForkSafety.singleton_class.prepend(memory::SPARED) if defined?(SQLite3::ForkSafety)
  end

  def eager
    return [] unless defined?(Rails.application)
    [Rails.application].select { |application| application.respond_to?(:eager_load!) }
  end

  def failure(error)
    "kimera: eager_load! failed (#{error.class}: #{error.message}); " \
      "lazily-autoloaded files may escape mutation"
  end
end
