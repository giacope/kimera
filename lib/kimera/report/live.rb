# frozen_string_literal: true

require_relative "log"
require "io/console"

class Kimera::Report::Live < Kimera::Report::Log
  REDRAW_EVERY = 0.1
  ERASE = "\r\e[K"
  CURSOR_UP = "\e[1A"

  def initialize(io, columns: nil)
    super(io)
    @columns = columns
    @rows = 1
  end

  def cadence = REDRAW_EVERY

  def commit
    return unless @drawn
    write("\n")
    @drawn = false
    @rows = 1
  end

  private

  def frame(text)
    prefix = erasure
    @rows = rows_for(text)
    "#{prefix}#{text}"
  end

  def wipe = write(erasure)

  def erasure
    ERASE + ((CURSOR_UP + ERASE) * (@rows - 1))
  end

  def rows_for(text)
    return 1 unless @columns&.positive?
    [(text.length + @columns - 1) / @columns, 1].max
  end
end
