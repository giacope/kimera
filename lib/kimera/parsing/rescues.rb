# frozen_string_literal: true

module Kimera
end

class Kimera::Rescues
  def initialize(clause)
    @clause = clause
  end

  def to_a = @clause ? [@clause, *Kimera::Rescues.new(@clause.subsequent).to_a] : []
end
