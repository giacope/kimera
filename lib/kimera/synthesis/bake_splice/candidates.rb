# frozen_string_literal: true

class Kimera::BakeSplice::Candidates
  def initialize(changed)
    @changed = changed
  end

  def to_a = [*Kimera::SpliceDiff.new(*changed.first).path.drop(1).reverse, *changed[0...-1]]

  private

  attr_reader :changed
end
