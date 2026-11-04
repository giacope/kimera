# frozen_string_literal: true

# A progress double that records each phase it is handed, the ticks the
# phase reports and the notes it is told, instead of drawing them.
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
