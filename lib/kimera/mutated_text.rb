# frozen_string_literal: true

module Kimera
end

class Kimera::MutatedText
  UNWRITTEN = "(kimera could not write this mutant's text; its label says what changed)"
  private_constant(:UNWRITTEN)

  def initialize(texts)
    @texts = texts
  end

  def to_s = @texts.fetch(0) { UNWRITTEN }
end
