# frozen_string_literal: true

require_relative "database_copies"
require_relative "memory_databases"
require_relative "parallel_databases"

module Kimera
  module Execution
  end
end

class Kimera::Execution::MirrorDatabase
  def initialize(slot, copies: Kimera::Execution::DatabaseCopies.new)
    @slot = slot
    @copies = copies
  end

  def prepare(slots)
    @copies.prepare(slots) if @copies.possible? && !parallel?
  end

  def adopt
    return unless @slot
    return @copies.adopt(@slot) unless parallel?
    require("active_record/test_databases")
    ActiveSupport::Testing::Parallelization.after_fork_hooks.each { |hook| hook.call(@slot) }
  rescue LoadError
    nil
  end

  private

  def parallel?(memory = Kimera::Execution::MemoryDatabases.new, parallel = Kimera::Execution::ParallelDatabases.new)
    return false unless defined?(ActiveSupport::Testing::Parallelization) && defined?(ActiveRecord::Base)
    return false if memory.current?
    parallel.enabled? && parallel.loadable?
  end
end
