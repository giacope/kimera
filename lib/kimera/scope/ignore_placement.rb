# frozen_string_literal: true

require_relative "ignore_drift"

class Kimera::IgnoreList::Placement
  include Kimera::IgnoreList::Drift

  attr_reader :rule

  def initialize(rule, pairs)
    @rule = rule
    @pairs = pairs
  end

  def ids = hits.map { |mutant, _point| mutant.id }

  def stale? = hits.empty? && !@pairs.empty?

  def moved
    return unless exact.empty?
    _mutant, point = drifted.first
    Kimera::IgnoreList::Shift.new(@rule, point.location.start_line) if point
  end

  private

  def anchors = @rule

  def matching(rule) = @pairs.select { |mutant, point| Kimera::IgnoreList.match?(rule, point, mutant) }
end
