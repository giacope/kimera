# frozen_string_literal: true

require_relative "ignore_drift"

class Kimera::IgnoreList::Placement
  include Kimera::IgnoreList::Drift

  def initialize(rule, pairs)
    @rule = rule
    @pairs = pairs
  end

  def ids = hits.map { |mutant, _point| mutant.to_i }

  def lapsed(kept) = stale? || !kept.include?(self) ? [@rule] : []

  def contested?(claimed) = exact.empty? && !hits.empty? && (ids - claimed).empty?

  def moved
    return [] unless exact.empty?
    drifted.first(1).map { |_mutant, point| Kimera::IgnoreList::Shift.new(@rule, point.to_h.dig("location", "start_line")) }
  end

  private

  def stale? = hits.empty? && (!@pairs.empty? || gone?)

  def anchors = @rule

  def gone?
    file = @rule[:file].to_s
    !file.empty? && !file.match?(/[*?\[{]/) && !File.exist?(file)
  end

  def matching(rule) = @pairs.select { |mutant, point| Kimera::IgnoreList::Match.new(point, mutant).rule?(rule) }
end
