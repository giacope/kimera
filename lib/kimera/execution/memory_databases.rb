# frozen_string_literal: true

module Kimera
  module Execution
  end
end

module Kimera::Execution::MemoryDatabases
  INHERITED =
    Module.new do
      define_method(:discard_pool!) do
        Kimera::Execution::MemoryDatabases.memory?(db_config) ? nil : super()
      end
    end

  class << self
    def keep!
      return unless defined?(ActiveRecord::ConnectionAdapters::PoolConfig)
      ActiveRecord::ConnectionAdapters::PoolConfig.prepend(INHERITED)
    end

    def memory?(config) = config.adapter.to_s.start_with?("sqlite") && config.database.to_s == ":memory:"
  end
end
