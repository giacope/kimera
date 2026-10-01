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

  def note(text)
    surface.note(text) if enabled? && !screen.interactive?
  end

  private

  def enabled? = screen.enabled?

  def screen = @_screen ||= Kimera::Report::Screen.of(@io, @enabled != false)

  def surface = @_surface ||= screen.surface

  def tally = @_tally ||= Kimera::Report::Tally.new

  def visible? = enabled? && tally.running?

  def due? = surface.due?(monotonic, cadence)

  def cadence = @redraw || surface.cadence

  def emit
    now = monotonic
    surface.paint(frame(now), now)
  end

  def frame(now) = screen.interactive? ? tally.line(now) : tally.plain(now)

  def monotonic = @clock.call
end
