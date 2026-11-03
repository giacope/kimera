# frozen_string_literal: true

require "fileutils"
require "kimera/execution/stack_dump"
require "timeout"
require "tmpdir"

# In-process: the spec arms its own process and signals itself, so the dump
# is written and read by the same code a worker and its pool run.
RSpec.describe(Kimera::Execution::StackDump) do
  let(:dir) { Dir.mktmpdir("kimera-stacks-spec") }
  let(:dump) { described_class.new(dir) }

  after { FileUtils.remove_entry(dir) }

  def trapped(handler)
    previous = Signal.trap(described_class::SIGNAL, handler)
    yield
  ensure
    Signal.trap(described_class::SIGNAL, previous || "DEFAULT")
  end

  # IGNORE underneath, so a dump that never armed times out instead of killing the suite.
  def armed(&)
    trapped("IGNORE") do
      dump.arm!
      yield
    end
  end

  # A thread as the dump reads one: its name, its frames and its status.
  def thread(name, frames: [], status: "sleep") = Struct.new(:name, :backtrace, :status).new(name, frames, status)

  def interrupted = armed { dump.take(Process.pid) }.fetch(0)

  it "answers the signal with the interrupted thread's own frames", :aggregate_failures do
    lines = interrupted.lines(chomp: true)

    expect(lines.first(2)).to(eq(["threads in the worker when it was killed:", "main thread (run):"]))
    expect(lines[2]).to(match(/stack_dump_spec\.rb:\d+:in '[^']*interrupted'\z/))
    expect(lines.grep(%r{/lib/kimera/execution/stack_dump\.rb})).to(be_empty)
  end

  it "consumes the dump, so a later worker with the same pid can't read it" do
    armed { dump.take(Process.pid) }
    expect(Dir.children(dir)).to(be_empty)
  end

  it "stops a thread's frames at Kimera's own runner" do
    harness = Kimera::Execution::Frames::HARNESS
    frames = ["app/x.rb:1:in 'a'", "#{harness}/execution/shift.rb:9:in 'b'", "app/y.rb:2:in 'c'"]
    text = dump.__send__(:describe, thread("w", frames: frames, status: "run"))
    expect(text).to(eq("thread w (run):\n  app/x.rb:1:in 'a'"))
  end

  it "skips the dump's own frames on the thread it interrupted" do
    frames = ["#{Kimera::Execution::Frames::HARNESS}/execution/stack_dump.rb:40:in 'write'", "app/x.rb:1:in 'a'"]
    expect(dump.__send__(:describe, thread("w", frames: frames))).to(eq("thread w (sleep):\n  app/x.rb:1:in 'a'"))
  end

  it "shows frames relative to the project and caps them per thread", :aggregate_failures do
    frames = Array.new(Kimera::Execution::Frames::MAX_FRAMES + 2) { |i| "#{Dir.pwd}/app/m.rb:#{i}:in 'm'" }
    lines = dump.__send__(:describe, thread(nil, frames: frames)).lines(chomp: true)
    expect([lines.first, lines[1], lines.size, lines.last]).to(
      match(
        [
          /\Athread \d+ \(sleep\):\z/, "  app/m.rb:0:in 'm'", Kimera::Execution::Frames::MAX_FRAMES + 2,
          "  … 2 more frame(s)"
        ]
      )
    )
  end

  it "labels a dead thread and one with no backtrace", :aggregate_failures do
    expect(dump.__send__(:describe, thread("gone", frames: nil, status: nil))).to(eq("thread gone (dead):"))
    expect(dump.__send__(:describe, thread("done", frames: nil, status: false))).to(eq("thread done (dead):"))
  end

  it "caps the threads it shows and counts the rest", :aggregate_failures do
    text = dump.__send__(:render, Array.new(described_class::MAX_THREADS + 3) { |i| thread("t#{i}") })

    expect(text.scan(/^thread t\d+ /).size).to(eq(described_class::MAX_THREADS))
    expect(text).to(end_with("\n(3 more thread(s))"))
  end

  it "shows every thread when there are no more than the cap" do
    text = dump.__send__(:render, Array.new(described_class::MAX_THREADS) { |i| thread("t#{i}") })
    expect(text).not_to(include("more thread"))
  end

  # A clock that reads each of +times+ in turn, and a pause that records.
  def patient(times, pauses)
    clock = times.dup
    described_class.new(dir, pause: ->(seconds) { pauses << seconds }, clock: -> { clock.shift })
  end

  it "polls for the dump until the grace period is up, then says why there is none", :aggregate_failures do
    pauses = []
    grace = described_class::GRACE
    silent = patient([0.0, grace / 2, grace, grace * 2], pauses)

    expect(trapped("IGNORE") { silent.take(Process.pid) }).to(eq([described_class::UNANSWERED]))
    expect(pauses).to(eq([described_class::POLL]))
  end

  it "stops polling as soon as the dump is there" do
    pauses = []
    File.write(File.join(dir, "#{Process.pid}.txt"), "ready")
    trapped("IGNORE") { patient([0.0], pauses).take(Process.pid) }
    expect(pauses).to(be_empty)
  end

  it "polls on the real clock by default", :aggregate_failures do
    stub_const("#{described_class}::GRACE", 0.05)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    expect(trapped("IGNORE") { dump.take(Process.pid) }).to(eq([described_class::UNANSWERED]))
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to(be_between(0.05, 1.0))
  end

  # A worker that writes its dump through a temporary file a little later; its pid.
  def late_writer(folder)
    fork do
      sleep(0.1)
      target = File.join(folder, "#{Process.pid}.txt")
      File.write("#{target}.tmp", "late")
      File.rename("#{target}.tmp", target)
      exit!(0)
    end
  end

  describe "a dump the worker is still writing" do
    after { Process.waitall }

    it "is waited for" do
      folder = dir
      expect(dump.__send__(:collect, File.join(folder, "#{late_writer(folder)}.txt"))).to(eq("late"))
    end
  end

  it "takes no dump from a worker that already exited" do
    pid = fork { exit!(0) }
    Process.wait(pid)
    expect(dump.take(pid)).to(eq([]))
  end

  it "reads a dump as UTF-8, replacing invalid bytes" do
    File.binwrite(File.join(dir, "#{Process.pid}.txt"), "caf\xC3\xA9 \xFF")
    expect(trapped("IGNORE") { dump.take(Process.pid) }).to(eq(["café �"]))
  end

  # A worker in the pool's own process group gets the signal alone; only a
  # worker that leads its own group has the group signalled.
  describe "asking a worker" do
    # Built before the forks, so every child writes to the parent's pipes.
    let!(:ready) { IO.pipe }
    let!(:heard) { IO.pipe }

    after { Process.waitall }

    # In a child: says +name+ on the heard pipe when the dump's signal comes, and exits; gives up after 10 s.
    def listen(name)
      Signal.trap(described_class::SIGNAL) do
        heard.last.puts(name)
        exit!(0)
      end
      ready.last.puts(name)
      sleep(10)
      exit!(1)
    end

    # In a child: leads a group of its own, with a child of its own in it.
    def family
      Process.setpgid(0, 0)
      fork { listen("grandchild") }
      listen("leader")
    end

    # A process in this group, and a group leader with a child of its own; the names of those that heard.
    def asked
      workers = [fork { listen("member") }, fork { family }]
      3.times { ready.first.gets }
      workers.each { |pid| dump.__send__(:ask, pid) }
      names
    end

    # The names the listeners said, once every one has exited.
    def names
      heard.last.close
      Timeout.timeout(15) { heard.first.readlines(chomp: true).sort }
    end

    it "signals a process in this group alone, and a group leader's whole group" do
      expect(asked).to(eq(%w[grandchild leader member]))
    end
  end
end
