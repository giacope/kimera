# frozen_string_literal: true

require_relative "phase"
require_relative "screen"

module Kimera
  module Report
  end
end

class Kimera::Report::Progress
  MONOTONIC = ->(reading = Process.clock_gettime(Process::CLOCK_MONOTONIC)) { reading }
  PACED = lambda(&:cadence)
  UNSEEN = ->(_status = nil) {}

  def initialize(io: $stderr, enabled: nil, cadence: PACED, clock: MONOTONIC)
    @io = io
    @enabled = enabled
    @cadence = cadence
    @clock = clock
  end

  def during(total, label = "mutants", &)
    started = @clock.call
    shown(Integer(total), label, &)
  ensure
    spent[label] += @clock.call - started
  end

  def phases = spent.transform_values { it.round(1) }

  def note(text)
    write(["kimera: #{text}\n"]) if enabled? && !screen.interactive?
  end

  private

  def enabled? = screen.enabled?

  def screen = @_screen ||= Kimera::Report::Screen.of(@io, @enabled != false)

  def spent = @_spent ||= Hash.new(0.0)

  def surface = @_surface ||= screen.surface

  def frame = Kimera::Report::Frame.new(@cadence.call(surface))

  def shown(count, label, &)
    return yield(UNSEEN) unless enabled? && count.positive?
    painted, ink = Kimera::Report::Phase.new(surface, Kimera::Report::Tally.new(count, label, @clock.call), frame)
      .painted(@clock.call)
    write(ink)
    ticking(painted, &)
  end

  def ticking(phase)
    lock = Mutex.new
    step = ->(status) { phase.ticked(status, @clock).tap { |_ticked, ink| write(ink) }.first }
    yield(->(status = nil) { lock.synchronize { phase = step.call(status) } })
  ensure
    write(phase.finished)
  end

  def write(ink)
    ink.each do |text|
      @io.print(text)
      @io.flush
    end
  end
end
