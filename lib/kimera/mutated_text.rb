# frozen_string_literal: true

module Kimera
end

class Kimera::MutatedText
  UNWRITTEN = "(kimera could not write this mutant's text; its label says what changed)"
  private_constant(:UNWRITTEN)

  def initialize(text)
    @text = text
  end

  def to_s = @text || UNWRITTEN
end
