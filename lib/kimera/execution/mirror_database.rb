# frozen_string_literal: true

require_relative "database_copies"
require_relative "memory_databases"
require_relative "parallel_databases"

module Kimera
  module Execution
  end
end

class Kimera::Execution::MirrorDatabase
  def initialize(slot)
    @slot = slot
  end

  def prepare(slots)
    copies.prepare(slots) if copies.possible? && !parallel?
  end

  def adopt
    return unless @slot
    return copies.adopt(@slot) unless parallel?
    require("active_record/test_databases")
    ActiveSupport::Testing::Parallelization.after_fork_hooks.each { |hook| hook.call(@slot) }
  rescue LoadError
    nil
  end

  private

  def copies = @_copies ||= Kimera::Execution::DatabaseCopies.new

  def parallel?
    return false unless defined?(ActiveSupport::Testing::Parallelization) && defined?(ActiveRecord::Base)
    return false if Kimera::Execution::MemoryDatabases.new.current?
    parallel = Kimera::Execution::ParallelDatabases.new
    parallel.enabled? && parallel.loadable?
  end
end
