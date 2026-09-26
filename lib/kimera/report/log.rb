# frozen_string_literal: true

module Kimera
  module Report
  end
end

class Kimera::Report::Log
  HEARTBEAT_EVERY = 10.0
  NEVER = -Float::INFINITY

  def initialize(io)
    @io = io
    @last = NEVER
    @drawn = false
  end

  def cadence = HEARTBEAT_EVERY

  def due?(now, cadence) = now - @last >= cadence

  def paint(text, now)
    write(frame(text))
    @drawn = true
    @last = now
  end

  def clear
    return unless @drawn
    wipe
    @drawn = false
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
