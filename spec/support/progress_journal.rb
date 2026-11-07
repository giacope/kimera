# frozen_string_literal: true

class ProgressJournal
  attr_reader :events

  def initialize(events = [])
    @events = events
  end

  def during(total, label = "mutants")
    events << [:start, total, label]
    yield(->(status = nil) { events << [:tick, status] })
  ensure
    events << [:finish]
  end

  def note(text) = events << [:note, text]

  def ticks = events.count { |event| event.first == :tick }
end
