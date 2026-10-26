# frozen_string_literal: true

require "delegate"

module Kimera
  module Frameworks
  end
end

class Kimera::Frameworks::NameExclusion < SimpleDelegator
  def initialize(adapter, patterns)
    super(adapter)
    @patterns = patterns
  end

  def test_ids
    adapter = __getobj__
    adapter.test_ids.reject do |id|
      expressions.any? do |pattern|
        pattern.match?(id) || pattern.match?(adapter.describe(id).to_s)
      end
    end
  end

  private

  def expressions = @_expressions ||= @patterns.map { |pattern| Regexp.new(pattern) }
end
