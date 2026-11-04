# frozen_string_literal: true

class Kimera::Reason::Guarded
  def self.tainted(text) = new(Kimera::Reason.unsafe(text), [])

  def self.orphaned(applied, detail) = new(Kimera::Reason.unmutatable(detail), applied)

  def initialize(reason, applied)
    @reason = reason
    @applied = applied
  end

  def mark!(marks, ids) = marks.safe? && !ids.intersect?(@applied) ? @reason.mark!(marks, ids) : []
end
