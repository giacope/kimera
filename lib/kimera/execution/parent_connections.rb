# frozen_string_literal: true

require_relative "memory_databases"

class Kimera::Execution::ParentConnections
  def release!
    return if Kimera::Execution::MemoryDatabases.new.current?
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
