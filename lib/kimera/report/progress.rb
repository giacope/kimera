# frozen_string_literal: true

require_relative "screen"
require_relative "tally"

module Kimera
  module Report
  end
end

class Kimera::Report::Progress
  MONOTONIC = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }

  def initialize(io: $stderr, enabled: nil, interval: nil, clock: MONOTONIC)
    @io = io
    @enabled = enabled
    @redraw = interval
    @clock = clock
  end

  def enabled? = screen.enabled?

  def start(total, label = "mutants")
    tally.begin!(Integer(total), label, monotonic)
    emit if visible?
  end

  def tick(status = nil)
    tally.count!(status)
    emit if visible? && (tally.complete? || due?)
  end

  def finish
    return surface.clear unless tally.complete?
    surface.commit
  end

  private

  def screen = @_screen ||= Kimera::Report::Screen.for(@io, @enabled)

  def surface = @_surface ||= screen.surface

  def tally = @_tally ||= Kimera::Report::Tally.new

  def visible? = enabled? && tally.running?

  def due? = surface.due?(monotonic, cadence)

  def cadence = @redraw || surface.cadence

  def emit = surface.paint(tally.line(monotonic), monotonic)

  def monotonic = @clock.call
end
