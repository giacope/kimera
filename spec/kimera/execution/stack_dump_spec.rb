# frozen_string_literal: true

require "fileutils"
require "kimera/execution/stack_dump"
require "timeout"
require "tmpdir"

RSpec.describe(Kimera::Execution::StackDump) do
  let(:dir) { Dir.mktmpdir("kimera-stacks-spec") }
  let(:dump) { described_class.new(dir) }

  def project
    FileUtils.mkdir_p(dir)
    yield([])
  ensure
    FileUtils.remove_entry(dir)
  end

  def trapped(handler)
    previous = Signal.trap(described_class::SIGNAL, handler)
    yield
  ensure
    Signal.trap(described_class::SIGNAL, previous || "DEFAULT")
  end

  def armed(&)
    trapped("IGNORE") do
      dump.arm!
      yield
    end
  end

  def thread(name, frames: [], status: "sleep") = Struct.new(:name, :backtrace, :status).new(name, frames, status)

  def interrupted = project { armed { dump.take(Process.pid) }.fetch(0) }

  def dumped(*threads)
    seen = described_class.new(dir, threads: -> { threads })
    text = project { trapped("IGNORE") { seen.tap(&:arm!).take(Process.pid) }.fetch(0) }
    text.delete_prefix("#{described_class::HEADER}\n")
  end

  it "answers the signal with the interrupted thread's own frames", :aggregate_failures do
    lines = interrupted.lines(chomp: true)

    expect(lines.first(2)).to(eq(["threads in the worker when it was killed:", "main thread (run):"]))
    expect(lines[2]).to(match(/stack_dump_spec\.rb:\d+:in '[^']*interrupted'\z/))
    expect(lines.grep(%r{/lib/kimera/execution/stack_dump\.rb})).to(be_empty)
  end

  it "consumes the dump, so a later worker with the same pid can't read it" do
    project do
      armed { dump.take(Process.pid) }
      expect(Dir.children(dir)).to(be_empty)
    end
  end

  it "stops a thread's frames at Kimera's own runner" do
    harness = Kimera::Execution::Frames::HARNESS
    frames = ["app/x.rb:1:in 'a'", "#{harness}/execution/shift.rb:9:in 'b'", "app/y.rb:2:in 'c'"]
    text = dumped(thread("w", frames: frames, status: "run"))
    expect(text).to(eq("thread w (run):\n  app/x.rb:1:in 'a'"))
  end

  it "skips the dump's own frames on the thread it interrupted" do
    frames = ["#{Kimera::Execution::Frames::HARNESS}/execution/stack_dump.rb:40:in 'write'", "app/x.rb:1:in 'a'"]
    expect(dumped(thread("w", frames: frames))).to(eq("thread w (sleep):\n  app/x.rb:1:in 'a'"))
  end

  it "shows frames relative to the project and caps them per thread", :aggregate_failures do
    frames = Array.new(Kimera::Execution::Frames::MAX_FRAMES + 2) { |i| "#{Dir.pwd}/app/m.rb:#{i}:in 'm'" }
    lines = dumped(thread(nil, frames: frames)).lines(chomp: true)
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
    expect(dumped(thread("gone", frames: nil, status: nil))).to(eq("thread gone (dead):"))
    expect(dumped(thread("done", frames: nil, status: false))).to(eq("thread done (dead):"))
  end

  it "caps the threads it shows and counts the rest", :aggregate_failures do
    text = dumped(*Array.new(described_class::MAX_THREADS + 3) { |i| thread("t#{i}") })

    expect(text.scan(/^thread t\d+ /).size).to(eq(described_class::MAX_THREADS))
    expect(text).to(end_with("\n(3 more thread(s))"))
  end

  it "shows every thread when there are no more than the cap" do
    text = dumped(*Array.new(described_class::MAX_THREADS) { |i| thread("t#{i}") })
    expect(text).not_to(include("more thread"))
  end

  def patient(times, pauses)
    clock = times.dup
    described_class.new(dir, pause: ->(seconds) { pauses << seconds }, clock: -> { clock.shift })
  end

  it "polls for the dump until the grace period is up, then says why there is none", :aggregate_failures do
    project do |pauses|
      silent = patient([0.0, 0.5, 1.0, 2.0].map { |share| share * described_class::GRACE }, pauses)

      expect(trapped("IGNORE") { silent.take(Process.pid) }).to(eq([described_class::UNANSWERED]))
      expect(pauses).to(eq([described_class::POLL]))
    end
  end

  it "stops polling as soon as the dump is there" do
    project do |pauses|
      File.write(File.join(dir, "#{Process.pid}.txt"), "ready")
      trapped("IGNORE") { patient([0.0], pauses).take(Process.pid) }
      expect(pauses).to(be_empty)
    end
  end

  def hurried
    stub_const("#{described_class}::GRACE", 0.05)
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  it "polls on the real clock by default", :aggregate_failures do
    project do
      started = hurried

      expect(trapped("IGNORE") { dump.take(Process.pid) }).to(eq([described_class::UNANSWERED]))
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to(be_between(0.05, 1.0))
    end
  end

  def finish(_seconds)
    target = File.join(dir, "#{Process.pid}.txt")
    File.write("#{target}.tmp", "late")
    File.rename("#{target}.tmp", target)
  end

  def late
    readings = [0.0] * 3
    described_class.new(dir, pause: method(:finish), clock: -> { readings.shift || Float::INFINITY })
  end

  describe "a dump the worker is still writing" do
    it "is waited for" do
      project do
        expect(trapped("IGNORE") { late.take(Process.pid) }).to(eq(["late"]))
      end
    end
  end

  it "takes no dump from a worker that already exited" do
    project do
      pid = fork { exit!(0) }
      Process.wait(pid)
      expect(dump.take(pid)).to(eq([]))
    end
  end

  it "reads a dump as UTF-8, replacing invalid bytes" do
    project do
      File.binwrite(File.join(dir, "#{Process.pid}.txt"), "caf\xC3\xA9 \xFF")
      expect(trapped("IGNORE") { dump.take(Process.pid) }).to(eq(["café �"]))
    end
  end

  describe "asking a worker" do
    let!(:ready) { IO.pipe }
    let!(:heard) { IO.pipe }

    def listen(name)
      Signal.trap(described_class::SIGNAL) do
        heard.last.puts(name)
        exit!(0)
      end
      ready.last.puts(name)
      Lifeline.new.hold
    end

    def family
      Process.setpgid(0, 0)
      fork { listen("grandchild") }
      listen("leader")
    end

    def asked
      workers = [fork { listen("member") }, fork { family }]
      3.times { ready.first.gets }
      hasty = described_class.new(dir, clock: -> { Float::INFINITY })
      workers.each { |pid| hasty.take(pid) }
      names
    ensure
      reap(workers)
    end

    def reap(workers)
      [workers.first, -workers.last].each { |target| stop(target) }
      workers.each { |pid| Process.wait(pid) }
    end

    def stop(target)
      Process.kill("KILL", target)
    rescue Errno::ESRCH
      target
    end

    def names
      heard.last.close
      Timeout.timeout(15) { heard.first.readlines(chomp: true).sort }
    end

    it "signals a process in this group alone, and a group leader's whole group" do
      project do
        expect(asked).to(eq(%w[grandchild leader member]))
      end
    end
  end
end
