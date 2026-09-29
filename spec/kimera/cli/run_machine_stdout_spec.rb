# frozen_string_literal: true

require "kimera/cli/run"
require "stringio"

# The suite loads in kimera's own process, so its prints and at_exit hooks
# (SimpleCov, Coveralls) shared stdout with a --format json report: thor's
# `kimera ci --format sarif` printed invalid SARIF.
RSpec.describe(Kimera::CLI::Run) do
  let(:report) { IO.pipe }
  let(:diagnostics) { IO.pipe }

  around { |example| swapped { example.run } }

  def swapped
    streams = [$stdout, $stderr]
    $stdout = report.last
    $stderr = diagnostics.last
    yield
  ensure
    $stdout, $stderr = streams
    [*report, *diagnostics].each { |io| io.close unless io.closed? }
  end

  def cli(io: $stdout) = described_class.new(io: io, errors: $stderr)

  def machine?(format, io: $stdout) = cli(io: io).__send__(:machine?, { format: format })

  it "detaches stdout for a machine format written to the real stdout", :aggregate_failures do
    expect(machine?("json")).to(be(true))
    expect(machine?("text")).to(be(false))
    expect(cli.__send__(:machine?, {})).to(be(false))
  end

  it "leaves a report stream it was handed alone", :aggregate_failures do
    expect(machine?("json", io: StringIO.new)).to(be(false))
    expect(machine?("json", io: diagnostics.last)).to(be(false))
  end

  it "keeps stdout for the report and sends everything else to stderr", :aggregate_failures do
    stdout = report.last
    stdout.sync = false
    stdout.write("early,")
    run = cli.tap { |detached| detached.__send__(:detach) }
    run.instance_variable_get(:@io).write("report")
    stdout.write("noise")
    stdout.flush
    expect(report.first.read_nonblock(100)).to(eq("early,report"))
    expect(diagnostics.first.read_nonblock(100)).to(eq("noise"))
  end
end
