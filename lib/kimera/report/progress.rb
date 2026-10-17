# frozen_string_literal: true

require_relative "screen"
require_relative "tally"

module Kimera
  module Report
  end
end

class Kimera::Report::Progress
  MONOTONIC = ->(reading = Process.clock_gettime(Process::CLOCK_MONOTONIC)) { reading }

  def initialize(io: $stderr, enabled: nil, interval: nil, clock: MONOTONIC)
    @io = io
    @enabled = enabled
    @redraw = interval
    @clock = clock
  end

  def start(total, label = "mutants")
    phases << Kimera::Report::Tally.new(Integer(total), label, @clock.call)
    emit if visible?
  end

  def tick(status = nil)
    tally.count!(status)
    emit if visible? && (tally.complete? || due?)
  end

  def finish
    return surface.clear unless phases.last.complete?
    surface.commit
  end

  def note(text)
    surface.note(text) if enabled? && !screen.interactive?
  end

  private

  def enabled? = screen.enabled?

  def screen = @_screen ||= Kimera::Report::Screen.of(@io, @enabled != false)

  def surface = @_surface ||= screen.surface

  def tally = phases.last

  def phases = @_phases ||= [Kimera::Report::Tally.new(0, nil, 0.0)]

  def visible? = enabled? && tally.running?

  def due? = surface.due?(@clock.call, cadence)

  def cadence = @redraw || surface.cadence

  def emit
    now = @clock.call
    surface.paint(frame(now), now)
  end

  def frame(now) = screen.interactive? ? tally.line(now) : tally.plain(now)
end
