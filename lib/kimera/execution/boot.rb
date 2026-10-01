# frozen_string_literal: true

require_relative "isolation"
require_relative "memory_databases"

class Kimera::Execution::Boot
  def initialize(adapter:, isolate:, errors: nil)
    @adapter = adapter
    @isolate = isolate
    @errors = errors
  end

  def suite(test_files)
    @adapter.source(test_files)
    @adapter.start
    load!
    keep!
  end

  def load!
    loader&.call
  rescue StandardError => error
    (@errors || $stderr).puts(failure(error))
  end

  def isolate(isolation)
    return isolation unless @isolate
    return isolation unless defined?(ActiveRecord::Base)
    Kimera::Execution::CompositeIsolation.new(
      [Kimera::Execution::TransactionIsolation.new(ActiveRecord::Base), isolation]
    )
  end

  private

  def keep!
    return unless defined?(ActiveRecord::ConnectionAdapters::PoolConfig)
    ActiveRecord::ConnectionAdapters::PoolConfig.prepend(Kimera::Execution::MemoryDatabases::INHERITED)
  end

  def application
    Rails.application
  rescue NameError
    nil
  end

  def loader
    application&.method(:eager_load!)
  rescue NameError
    nil
  end

  def failure(error)
    "kimera: eager_load! failed (#{error.class}: #{error.message}); " \
      "lazily-autoloaded files may escape mutation"
  end
end
