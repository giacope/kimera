# frozen_string_literal: true

require_relative "memory_databases"

# The process that loaded the suite forks workers and spawns mirrors. A
# connection it keeps open (one its suite opened while loading, or a
# migration's advisory-lock session) is shared by every fork, and blocks a
# mirror whose suite drops and re-creates the test database at load.
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
