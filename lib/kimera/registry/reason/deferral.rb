# frozen_string_literal: true

class Kimera::Reason::Deferral
  def initialize(coverage, unreached, reached)
    @coverage = coverage
    @unreached = unreached
    @reached = reached
  end

  def mark!(marks, ids) = (uncovered?(ids) ? @unreached : @reached).mark!(marks, ids)

  private

  def uncovered?(ids) = ids.all? { |id| @coverage.fetch(id) { @coverage.fetch(id.to_s, []) }.empty? }
end
