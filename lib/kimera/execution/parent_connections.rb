# frozen_string_literal: true

require_relative "memory_databases"

class Kimera::Execution::ParentConnections
  def release!(databases = Kimera::Execution::MemoryDatabases.new)
    return [] if !defined?(ActiveRecord::Base) || databases.current?
    pools.select { |pool| let_go(pool) }
  end

  private

  def let_go(pool)
    pool.disconnect!
    true
  rescue ActiveRecord::ExclusiveConnectionTimeoutError
    false
  end

  def pools
    handler = ActiveRecord::Base.connection_handler
    handler.respond_to?(:each_connection_pool) ? handler.each_connection_pool.to_a : handler.connection_pool_list
  end
end
