# frozen_string_literal: true

require "kimera/execution/suite_capture"
require "stringio"
require "tmpdir"

# K3-2: doctor waited forever on a suite that never exits.
RSpec.describe(Kimera::Execution::SuiteCapture, :aggregate_failures) do
  let(:said) { StringIO.new }
  let(:capture) { described_class.new(said) }

  # Elapsed seconds since the start, one reading per poll.
  def polled(*elapsed, limit:)
    allow(capture).to(receive(:now).and_return(0.0, *elapsed))
    allow(capture).to(receive(:sleep))
    Dir.mktmpdir { |root| capture.call({}, "sleep", "30", chdir: root, limit: limit) }
  end

  it "polls until the limit, sleeping between polls, then stops the suite" do
    _output, status = polled(0.6, 0.7, limit: 0.6)
    expect(status.success?).to(be(false))
    expect(capture).to(have_received(:sleep).with(described_class::POLL).once)
  end

  it "says the suite is still running every 150 polls, half a minute of them" do
    polled(*([1.0] * 300), 99.0, limit: 90)
    expect(said.string).to(eq("kimera: the suite is still running (1 s)…\n" * 2))
  end

  # A suite's background child shares its process group.
  def orphan(limit)
    Dir.mktmpdir do |root|
      output, = described_class.new(said).call({}, "sh", "-c", "sleep 30 & echo $!", chdir: root, limit: limit)
      pid = Integer(output.lines.first)
      sleep(0.2)
      state = File.read("/proc/#{pid}/stat").split[2]
      return state == "Z" ? :gone : :alive
    rescue Errno::ENOENT
      return :gone
    end
  end

  it "kills a suite that outlives its limit" do
    Dir.mktmpdir do |root|
      described_class.new(said).call({}, "sh", "-c", "echo $$ > #{root}/pid; exec sleep 30", chdir: root, limit: 0.5)
      expect(File.exist?("/proc/#{Integer(File.read(File.join(root, "pid")))}")).to(be(false))
    end
  end

  it "leaves nothing of the suite's process group behind", :aggregate_failures do
    expect(orphan(nil)).to(eq(:gone))
    expect(orphan(10)).to(eq(:gone))
  end
end
