# frozen_string_literal: true

require_relative "surface"
require "io/console"

class Kimera::Report::Live
  include Kimera::Report::Surface

  REDRAW_EVERY = 0.1
  ERASE = "\r\e[K"
  CURSOR_UP = "\e[1A"

  def initialize(io, columns: nil)
    @io = io
    @columns = columns
  end

  def cadence = REDRAW_EVERY

  def commit
    return unless shown.drawn
    write("\n")
    shown.drawn = false
    shown.rows = 1
  end

  private

  def frame(text)
    prefix = erasure
    shown.rows = rows_for(text)
    "#{prefix}#{text}"
  end

  def wipe = write(erasure)

  def erasure
    ERASE + ((CURSOR_UP + ERASE) * (shown.rows - 1))
  end

  def rows_for(text)
    return 1 unless @columns&.positive?
    [(text.length + @columns - 1) / @columns, 1].max
  end
end
