# frozen_string_literal: true

require_relative "tally"

class Kimera::RegistryScan::Numbering
  def point = points.next

  def mutant = mutants.next

  private

  def points = @_points ||= Kimera::RegistryScan::Tally.new

  def mutants = @_mutants ||= Kimera::RegistryScan::Tally.new
end
