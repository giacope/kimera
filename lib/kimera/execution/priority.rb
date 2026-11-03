# frozen_string_literal: true

module Kimera
  module Execution
  end
end

class Kimera::Execution::Priority
  def initialize(coverage)
    @coverage = coverage
  end

  def order(ids) = ids.sort_by { |id| -count(id) }

  private

  def count(id) = recorded.fetch(id) { recorded.fetch(id.to_s, []) }.size

  def recorded = @_recorded ||= @coverage.to_h
end
