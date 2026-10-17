# frozen_string_literal: true

module Kimera
  module Report
  end
end

class Kimera::Report::Log
  HEARTBEAT_EVERY = 30.0
  NEVER = -Float::INFINITY

  def initialize(io)
    @io = io
    @shown = { painted: NEVER, drawn: false, rows: 1 }
  end

  def cadence = HEARTBEAT_EVERY

  def due?(now, cadence) = now - @shown[:painted] >= cadence

  def note(text) = write("kimera: #{text}\n")

  def paint(text, now)
    write(frame(text))
    @shown.update(drawn: true, painted: now)
  end

  def clear
    return unless @shown[:drawn]
    wipe
    @shown[:drawn] = false
  end

  def commit = clear

  private

  def frame(text) = "#{text}\n"

  def wipe = @io.flush

  def write(text)
    @io.print(text)
    @io.flush
  end
end
