# frozen_string_literal: true

require_relative "mirror_database"
require_relative "numbered_databases"
require_relative "parent_connections"

module Kimera
  module Execution
  end
end

class Kimera::Execution::MirrorSlots
  def initialize(
    jobs, connections: Kimera::Execution::ParentConnections.new, numbered: Kimera::Execution::NumberedDatabases.new,
    mirror: Kimera::Execution::MirrorDatabase.new(nil)
  )
    @jobs = jobs
    @connections = connections
    @numbered = numbered
    @mirror = mirror
  end

  def release! = @connections.release!

  def prepare
    return (1...@jobs).each { |slot| @numbered.prepare(slot) } if @numbered.numbered?
    @mirror.prepare(1...@jobs)
  end
end
