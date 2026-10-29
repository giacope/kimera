# frozen_string_literal: true

module Kimera
  module Report
  end
end

class Kimera::Report::Surface
  NEVER = -Float::INFINITY
  Shown = Struct.new(:painted, :drawn, :rows, keyword_init: true)

  def initialize(io, shown = Shown.new(painted: NEVER, drawn: false, rows: 1))
    @io = io
    @shown = shown
  end

  def due?(now, cadence) = now - shown.painted >= cadence

  def note(text) = write("kimera: #{text}\n")

  def paint(text, now)
    write(frame(text))
    shown.drawn = true
    shown.painted = now
  end

  def clear
    return unless shown.drawn
    wipe
    shown.drawn = false
  end

  private

  attr_reader :shown

  def write(text)
    @io.print(text)
    @io.flush
  end
end
