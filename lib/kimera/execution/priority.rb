# frozen_string_literal: true

module Kimera
  module Execution
  end
end

class Kimera::Execution::Priority
  def initialize(coverage)
    @coverage = coverage
  end

  def order(ids)
    return ids unless @coverage
    ids.sort_by { |id| -count(id) }
  end

  private

  def count(id)
    @coverage.fetch(id) { @coverage.fetch(id.to_s, []) }.size
  end
end
