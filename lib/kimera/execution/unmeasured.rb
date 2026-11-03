# frozen_string_literal: true

module Kimera
  module Execution
  end
end

class Kimera::Execution::Unmeasured
  def initialize(adapter)
    @adapter = adapter
  end

  def fetch(_id, *, &) = @adapter.test_ids

  def to_h = {}
end
