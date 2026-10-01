# frozen_string_literal: true

module Kimera
  module Execution
  end
end

class Kimera::Execution::IsolatedOutcome
  attr_reader :status, :failing, :detail

  def initialize(status, failing = nil, detail = nil)
    @status = status
    @failing = failing
    @detail = detail
  end

  def explain(limit)
    return "timed out after #{limit}s" if status == :timeout
    named = Array(failing)
    return "failing: #{named.join(", ")}" if named.any?
    detail || "the test child failed without naming a test"
  end
end

require_relative "isolated_outcome/ruling"
