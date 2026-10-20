# frozen_string_literal: true

module Kimera
  module Execution
  end
end

class Kimera::Execution::MirrorDatabase
  def initialize(slot)
    @slot = slot
  end

  def adopt
    return unless @slot && parallel?
    require("active_record/test_databases")
    ActiveSupport::Testing::Parallelization.after_fork_hooks.each { |hook| hook.call(@slot) }
  rescue LoadError
    nil
  end

  private

  def parallel?
    return false unless defined?(ActiveSupport::Testing::Parallelization) && defined?(ActiveRecord::Base)
    ActiveSupport.parallelize_test_databases
  rescue NoMethodError
    false
  end
end
