# frozen_string_literal: true

require "kimera/report/progress"
require "stringio"

RSpec.describe(Kimera::Report::Progress) do
  # In-place redraw only engages on a tty; a plain StringIO gets heartbeat lines.
  def fake_tty
    io = StringIO.new
    def io.tty? = true
    io
  end

  # interval: 0 disables throttling.
  def progress(io: fake_tty, enabled: true, interval: 0, clock: nil)
    opts = { io: io, enabled: enabled, interval: interval }
    opts[:clock] = clock if clock
    [described_class.new(**opts), io]
  end

  def frames(io)
    io.string.split("\r\e[K").reject(&:empty?)
  end

  def drive(total, label, ticks: 0, status: nil, finish: false, **)
    bar, io = progress(**)
    bar.start(total, label)
    ticks.times { status ? bar.tick(status) : bar.tick }
    bar.finish if finish
    [bar, io]
  end

  it "stays completely silent when disabled" do
    _bar, io = drive(10, "mutants", ticks: 10, status: :killed, finish: true, enabled: false)
    expect(io.string).to(be_empty)
  end

  def exercise(io, total: 5, label: "mutants", status: :killed)
    bar = described_class.new(io: io)
    bar.start(total, label)
    bar.tick(status)
    bar.finish
    bar
  end

  it "defaults to plain lines on a non-tty stream", :aggregate_failures do
    io = StringIO.new
    exercise(io)
    expect(io.string.lines).to(all(start_with("kimera: mutants ")))
    expect(io.string).not_to(include("\r", "["))
  end

  it "stays silent on a non-tty stream when disabled explicitly" do
    io = StringIO.new
    described_class.new(io: io, enabled: false).tap { |bar| bar.start(2, "mutants") }.note("phase")
    expect(io.string).to(be_empty)
  end

  it "auto-enables when the stream is a tty" do
    bar, io = progress
    bar.start(5, "mutants")
    expect(io.string).to(include("0/5"))
  end

  it "prints heartbeat lines instead of redrawing on a non-tty stream", :aggregate_failures do
    _bar, io = drive(2, "mutants", ticks: 2, status: :killed, finish: true, io: StringIO.new)

    expect(io.string).not_to(include("\r\e[K"))
    lines = io.string.lines
    expect(lines.first).to(eq("kimera: mutants 0/2 0%  0:00 elapsed\n"))
    expect(lines.last).to(include("2/2", "100%", "killed=2"))
  end

  # Every tick but the last lands at t=0, inside the heartbeat window; the last at `at`.
  def plain(total, ticks, at:, label: "mutants (warm)")
    now = 0.0
    io = StringIO.new
    bar = described_class.new(io: io, clock: -> { now })
    bar.start(total, label)
    ticks[...-1].each { |status| bar.tick(status) }
    now = at
    bar.tick(ticks.last)
    io.string.lines
  end

  it "renders a plain line with counts, rate, ETA and elapsed time" do
    ticks = ([:killed] * 801) + ([:survived] * 312) + ([:no_coverage] * 97)
    line = "kimera: mutants (warm) 1210/4124 29%  killed=801 survived=312 no_coverage=97  1.7/s  ETA 29:03  " \
      "12:04 elapsed"
    expect(plain(4124, ticks, at: 724.0).last).to(eq("#{line}\n"))
  end

  it "closes a phase with a final plain line and no ETA" do
    expect(plain(2, %i[killed survived], at: 5.0).last).to(
      eq("kimera: mutants (warm) 2/2 100%  killed=1 survived=1  0.4/s  0:05 elapsed\n")
    )
  end

  it "prints a plain heartbeat every 30 seconds, not sooner", :aggregate_failures do
    expect(Kimera::Report::Log::HEARTBEAT_EVERY).to(eq(30.0))
    expect(plain(10, [:killed], at: 29.9).size).to(eq(1))
    expect(plain(10, [:killed], at: 30.0).size).to(eq(2))
  end

  it "writes a note as its own plain line" do
    io = StringIO.new
    described_class.new(io: io).note("isolated baseline (unmutated mirror)")
    expect(io.string).to(eq("kimera: isolated baseline (unmutated mirror)\n"))
  end

  it "keeps notes off a live bar" do
    bar, io = progress
    bar.note("isolated baseline (unmutated mirror)")
    expect(io.string).to(be_empty)
  end

  # Ticks at t=0 (always suppressed), then again at `elapsed`.
  def heartbeat(elapsed, tty: false)
    now = 0.0
    io = tty ? fake_tty : StringIO.new
    bar = described_class.new(io: io, enabled: true, clock: -> { now })
    bar.start(10, "mutants")
    bar.tick(:killed)
    now = elapsed
    bar.tick(:killed)
    io
  end

  it "throttles non-tty heartbeats to the heartbeat interval by default" do
    io = heartbeat(Kimera::Report::Log::HEARTBEAT_EVERY)
    expect(io.string.lines.size).to(eq(2)) # start frame + one heartbeat
  end

  it "keeps the fast redraw window only on a tty", :aggregate_failures do
    io = heartbeat(Kimera::Report::Live::REDRAW_EVERY * 2) # a tty would redraw here; the heartbeat must not
    expect(io.string.lines.size).to(eq(1))

    tty = heartbeat(Kimera::Report::Live::REDRAW_EVERY, tty: true)
    expect(frames(tty).size).to(eq(2))
  end

  it "redraws the line in place with label, counts, and percent", :aggregate_failures do
    _, io = drive(4, "mutants", ticks: 4, status: :killed)

    expect(frames(io).first).to(start_with("mutants ["))
    expect(frames(io).last).to(include("4/4", "100%", "killed=4", "survived=0"))
  end

  it "renders the exact frame for a partially complete pass", :aggregate_failures do
    _, io = drive(4, "mutants", ticks: 1, status: :killed)

    last = frames(io).last
    expect(last).to(start_with("mutants [=====>                  ]  1/4  25%  killed=1 survived=0"))
    expect(last).to(match(/  \d+:\d{2}\z/)) # elapsed clock closes the line
  end

  def fill(count, total)
    _, io = drive(total, "m", ticks: count)
    frames(io).last[/\[.*?\]/]
  end

  # 24-wide bar, keyed by [count, total].
  def geometries
    {
      [0, 4] => "[                        ]", # empty, no head
      [1, 4] => "[=====>                  ]", # filled 6
      [2, 4] => "[===========>            ]", # filled 12
      [4, 4] => "[========================]", # full, no head
      [1, 24] => "[>                       ]", # filled 1: head only
      [23, 24] => "[======================> ]" # filled 23: head near end
    }
  end

  it "draws the exact bar at fill boundaries", :aggregate_failures do
    geometries.each { |(count, total), bar| expect(fill(count, total)).to(eq(bar)) }
  end

  def boundary
    now = 0.0
    bar, io = progress(interval: 0.1, clock: -> { now })
    bar.start(10, "mutants") # draws at t=0
    now = 0.05
    bar.tick # inside the window: skipped
    now = 0.1
    bar.tick # at the edge: drawn
    frames(io)
  end

  it "skips a tick inside the throttle window and draws at its edge", :aggregate_failures do
    drawn = boundary
    expect(drawn.size).to(eq(2))
    expect(drawn.last).to(include("2/10"))
  end

  def phases
    bar, io = progress(interval: 600)
    bar.start(2, "baseline")
    2.times { bar.tick }
    bar.start(3, "mutants")
    frames(io)
  end

  it "draws phase-start and final frames despite the throttle", :aggregate_failures do
    drawn = phases
    expect(drawn.size).to(eq(3)) # tick 1/2 was throttled away
    expect(drawn[0]).to(include("baseline", "0/2"))
    expect(drawn[1]).to(include("baseline", "2/2", "100%"))
    expect(drawn[2]).to(include("mutants", "0/3"))
  end

  it "commits a completed phase only once for repeated finishes" do
    bar, io = drive(1, "mutants", ticks: 1, finish: true)
    bar.finish
    transcript = io.string
    expect([transcript.scan("\r\e[K").size, transcript.end_with?("\n")]).to(eq([2, true]))
  end

  it "does not record a status count when ticked without one", :aggregate_failures do
    bar, io = drive(2, "baseline", ticks: 1)
    bar.tick(:killed)

    last = frames(io).last
    expect(last).to(include("killed=1 survived=0"))
    expect(last).not_to(include("=2"))
  end

  it "shows no status counts for a pass ticked only without statuses" do
    _, io = drive(2, "baseline", ticks: 1)
    expect(frames(io).last).not_to(match(/=\d/))
  end

  def started
    bar, io = progress
    bar.start(2, "mutants")
    [bar, io]
  end

  it "shows timeout/error counts only once they are nonzero", :aggregate_failures do
    bar, io = started
    bar.tick(:killed)
    expect(io.string).not_to(include("timeout="))
    bar.tick(:timeout)
    expect(io.string).to(include("timeout=1"))
  end

  it "keeps a completed phase on its own line for the report or next phase" do
    _, io = drive(1, "baseline", ticks: 1, finish: true)
    expect(io.string).to(match(%r{baseline \[========================\]  1/1  100%.*  0:00\n\z}))
  end

  it "keeps a completed phase visible when the next phase starts" do
    bar, io = progress(interval: 0)
    bar.start(1, "baseline")
    bar.tick
    bar.finish
    bar.start(1, "mutants (warm)")

    expect(io.string).to(match(%r{baseline \[========================\]  1/1  100%.*\n\r\e\[Kmutants \(warm\)}m))
  end

  it "erases every terminal row occupied by a wrapped frame" do
    io = fake_tty
    allow(io).to(receive(:winsize).and_return([24, 20]))
    bar = described_class.new(io: io, enabled: true, interval: 0)
    bar.start(2, "mutants (isolated)")
    first = io.string.dup
    rows = (first.delete_prefix("\r\e[K").length + 19) / 20

    bar.tick(:killed)

    upward = "\e[1A\r\e[K" * (rows - 1)
    erasure = "\r\e[K#{upward}"
    expect(io.string.delete_prefix(first)).to(start_with(erasure))
  end

  it "does not emit the erase sequence when nothing was drawn" do
    _, io = drive(1, "mutants", finish: true, enabled: false)
    expect(io.string).to(be_empty)
  end

  it "handles an empty pass without drawing or dividing by zero" do
    _, io = drive(0, "mutants", finish: true)
    expect(io.string).to(be_empty)
  end

  def restart
    bar, io = drive(2, "baseline", ticks: 2)
    bar.start(3, "mutants")
    bar.tick(:survived)
    frames(io).last
  end

  it "resets counters when a new phase starts", :aggregate_failures do
    last = restart
    expect(last).to(include("mutants", "1/3", "survived=1"))
    expect(last).not_to(include("baseline"))
  end

  def elapsed(start_at, tick_at)
    now = start_at
    bar, io = progress(clock: -> { now })
    bar.start(2, "mutants")
    now = tick_at
    bar.tick(:killed)
    frames(io).last
  end

  it "renders elapsed time as MM:SS from the monotonic delta" do
    # 3600s tells 60 from 59 or 61. The nonzero base catches `-` => `+`.
    expect(elapsed(1000.0, 4600.0)).to(end_with("  60:00"))
  end

  it "pads the seconds field to two digits" do
    expect(elapsed(0.0, 63.0)).to(end_with("  1:03"))
  end

  it "lists each status exactly once even when it is both ticked and always-shown", :aggregate_failures do
    _, io = drive(1, "mutants", ticks: 1, status: :killed)

    last = frames(io).last
    expect(last.scan("killed=").size).to(eq(1))
    expect(last.scan("survived=").size).to(eq(1))
    expect(last).to(include("killed=1 survived=0"))
  end

  # An unflushed frame is invisible to whoever is watching the run.
  def watched(tty:)
    io = StringIO.new
    flushes = [0]
    io.define_singleton_method(:flushes) { flushes[0] }
    io.define_singleton_method(:flush) { flushes[0] += 1 }
    io.define_singleton_method(:tty?) { true } if tty
    io
  end

  it "flushes the stream after every frame it paints" do
    io = watched(tty: true)
    bar = described_class.new(io: io, enabled: true, interval: 0)
    bar.start(2, "mutants")
    bar.tick(:killed)
    expect(io.flushes).to(eq(2))
  end

  it "flushes once more when a heartbeat run finishes", :aggregate_failures do
    io = watched(tty: false)
    bar = described_class.new(io: io, enabled: true, interval: 0)
    bar.start(1, "mutants")
    painted = io.flushes
    bar.finish
    expect(painted).to(eq(1))
    expect(io.flushes).to(eq(2))
  end
end
