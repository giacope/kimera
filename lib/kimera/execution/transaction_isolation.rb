# frozen_string_literal: true

require_relative "isolation"

class Kimera::Execution::TransactionIsolation; end
class Kimera::Execution::TransactionIsolation::Rollback < StandardError; end

class Kimera::Execution::TransactionIsolation
  def initialize(owner)
    @owner = owner
  end

  def around
    result = nil
    rollback { result = yield }
    result
  end

  def reset!; end

  private

  def rollback(&)
    @owner.transaction(requires_new: true) { unwind(&) }
  rescue Rollback
    nil
  end

  def unwind
    yield
    raise(Rollback)
  end
end
