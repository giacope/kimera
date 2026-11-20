# frozen_string_literal: true

require "kimera/execution/suite_capture"
require "stringio"
require "timeout"
require "tmpdir"

RSpec.describe(Kimera::Execution::SuiteCapture, :aggregate_failures) do
  let(:said) { StringIO.new }

  def polled(*elapsed, limit:, clock: FakeClock.new(0.0, *elapsed))
    capture = described_class.new(said, Kimera::Execution::SuiteEnv.new, clock)
    Dir.mktmpdir { |root| capture.timed("sleep", "30", chdir: root, limit: limit) }
  end

  it "polls until the limit, sleeping between polls, then stops the suite" do
    clock = FakeClock.new(0.0, 0.6, 0.7)
    _output, status = polled(limit: 0.6, clock: clock)
    expect([status.success?, clock.paused]).to(eq([false, 1]))
  end

  it "says the suite is still running every 150 polls, half a minute of them" do
    polled(*([1.0] * 300), 99.0, limit: 90)
    expect(said.string).to(eq("kimera: the suite is still running (1 s)…\n" * 2))
  end

  def suite(said, limit, *command, chdir:)
    capture = described_class.new(said)
    limit ? capture.timed(*command, chdir: chdir, limit: limit) : capture.call(*command, chdir: chdir)
  end

  def orphan(limit)
    Dir.mktmpdir do |root|
      output, = suite(said, limit, "sh", "-c", "sleep 30 & echo $!", chdir: root)
      gone?(Integer(output.lines.first)) ? :gone : :alive
    end
  end

  it "kills a suite that outlives its limit" do
    Dir.mktmpdir do |root|
      described_class.new(said).timed("sh", "-c", "echo $$ > #{root}/pid; exec sleep 30", chdir: root, limit: 0.5)
      expect(File.exist?("/proc/#{Integer(File.read(File.join(root, "pid")))}")).to(be(false))
    end
  end

  it "leaves nothing of the suite's process group behind", :aggregate_failures do
    expect(orphan(nil)).to(eq(:gone))
    expect(orphan(10)).to(eq(:gone))
  end

  def interrupted(limit)
    Dir.mktmpdir do |root|
      pidfile = File.join(root, "pid")
      alarm(pidfile)
      halted(limit, pidfile, root)
    end
  end

  def alarm(pidfile)
    waiter = Thread.current
    Thread.new do
      sleep(0.05) until File.size?(pidfile)
      waiter.raise(Interrupt)
    end
  end

  def halted(limit, pidfile, root)
    suite(said, limit, "sh", "-c", "sleep 30 & echo $! > #{pidfile}; wait", chdir: root)
    :finished
  rescue Interrupt
    settled(Integer(File.read(pidfile)))
  end

  def settled(pid) = gone?(pid) ? :stopped : :running

  def gone?(pid)
    Timeout.timeout(5) { sleep(0.01) until dead?(pid) }
    true
  rescue Timeout::Error
    false
  end

  def dead?(pid)
    File.read("/proc/#{pid}/stat").split[2] == "Z"
  rescue Errno::ENOENT, Errno::ESRCH
    true
  end

  it "stops the suite's process group when it is interrupted, and lets the interrupt through", :aggregate_failures do
    expect(interrupted(nil)).to(eq(:stopped))
    expect(interrupted(10)).to(eq(:stopped))
  end
end
