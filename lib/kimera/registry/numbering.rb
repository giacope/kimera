# frozen_string_literal: true

class Kimera::RegistryScan::Numbering
  def initialize(first = 1)
    @first = first
  end

  def point = points.next

  def mutant = mutants.next

  private

  def points = @_points ||= (1..).each

  def mutants = @_mutants ||= (@first..).each
end
