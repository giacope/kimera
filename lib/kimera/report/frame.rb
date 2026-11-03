# frozen_string_literal: true

module Kimera
  module Report
  end
end

class Kimera::Report::Frame
  NEVER = -Float::INFINITY

  def initialize(cadence, painted = NEVER, text = "")
    @cadence = cadence
    @painted = painted
    @text = text
  end

  def due?(now) = now - @painted >= @cadence

  def over(text, now) = self.class.new(@cadence, now, text)

  def drawn? = !@text.empty?

  def rows(columns)
    return 1 unless columns.positive?
    [(@text.length + columns - 1) / columns, 1].max
  end
end
