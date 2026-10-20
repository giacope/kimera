# frozen_string_literal: true

require "kimera/cli"
require "kimera/execution/suite_capture"
require "tmpdir"

# doctor runs the suite as a plain command. A suite that leaves a process
# running (a test helper's redis-server) must not keep doctor waiting on it.
RSpec.describe(Kimera::Execution::SuiteCapture) do
  subject(:capture) { described_class.new }

  def ruby(script) = [Gem.ruby, "-e", script]

  # A killed process whose parent is gone may linger as a zombie until init
  # reaps it; that is dead too.
  def alive?(pid)
    Process.kill(0, pid)
    stat = "/proc/#{pid}/stat"
    !File.exist?(stat) || File.read(stat).split(") ").last.split.first != "Z"
  rescue Errno::ESRCH, Errno::ENOENT
    false
  end

  # A signal arrives asynchronously; give the killed process a moment.
  def gone?(pid, deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2)
    sleep(0.02) while alive?(pid) && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
    !alive?(pid)
  end

  it "returns the command's output, both streams, and its status", :aggregate_failures do
    output, status = capture.call({}, *ruby("puts 'out'; warn 'err'; exit 3"), chdir: Dir.pwd)
    expect(output.lines.map(&:chomp)).to(contain_exactly("out", "err"))
    expect(status.exitstatus).to(eq(3))
  end

  it "passes the environment and runs in the given directory" do
    Dir.mktmpdir do |dir|
      output, = capture.call({ "KIMERA" => "1" }, *ruby("print ENV['KIMERA'], ' ', Dir.pwd"), chdir: dir)
      expect(output).to(eq("1 #{File.realpath(dir)}"))
    end
  end

  it "returns when the command exits, though a process it started still holds the output", :aggregate_failures do
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    output, status = capture.call({}, *ruby("puts spawn('sleep', '30'); $stdout.flush"), chdir: Dir.pwd)
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to(be < 10)
    expect(status).to(be_success)
    expect(gone?(Integer(output))).to(be(true))
  end

  it "reads the output as UTF-8 and scrubs bytes that are not" do
    output, = capture.call({}, *ruby("$stdout.binmode; $stdout.write(\"caf\\xC3\\xA9 \\xFF\")"), chdir: Dir.pwd)
    expect(output).to(eq("café \uFFFD"))
  end

  it "raises when the command does not exist" do
    expect { capture.call({}, "kimera-no-such-command", chdir: Dir.pwd) }.to(raise_error(Errno::ENOENT))
  end
end
