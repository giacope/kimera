# frozen_string_literal: true

require_relative "memory_databases"

class Kimera::Execution::ParentConnections
  def release!(databases = Kimera::Execution::MemoryDatabases.new)
    return if databases.current?
    pools.each(&:disconnect!)
  rescue StandardError
    nil
  end

  private

  def pools
    handler = ActiveRecord::Base.connection_handler
    handler.respond_to?(:each_connection_pool) ? handler.each_connection_pool.to_a : handler.connection_pool_list
  end
end
