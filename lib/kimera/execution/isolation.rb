# frozen_string_literal: true

module Kimera
  module Execution
  end
end

class Kimera::Execution::Isolation
  def around
    yield
  end

  def reset!; end
end

require_relative "composite_isolation"
require_relative "transaction_isolation"
