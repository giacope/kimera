# frozen_string_literal: true

require "kimera/cli/run"
require "stringio"
require "tmpdir"

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

  def cli(io: $stdout) = described_class.new(io: io, errors: $stderr, bench: FakeBench.new)

  def machine?(format, io: $stdout) = cli(io: io).__send__(:machine?, { format: format }, Kimera::CLI::Run::Streams.new)

  it "detaches stdout for a machine format written to the real stdout", :aggregate_failures do
    expect(machine?("json")).to(be(true))
    expect(machine?("text")).to(be(false))
    expect(cli.__send__(:machine?, {}, Kimera::CLI::Run::Streams.new)).to(be(false))
  end

  it "leaves a report stream it was handed alone", :aggregate_failures do
    expect(machine?("json", io: StringIO.new)).to(be(false))
    expect(machine?("json", io: diagnostics.last)).to(be(false))
  end

  def full(*argv) = ended(cli.run(["calc.rb", *argv]))

  def project(&)
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        File.write("calc.rb", "def m(a, b)\n  a > b\nend\n")
        FileUtils.mkdir_p("spec")
        File.write("spec/calc_spec.rb", "")
        yield
      end
    end
  end

  it "detaches stdout for the whole of a --format json run", :aggregate_failures do
    project { full("--format", "json") }
    report.last.write("later")
    report.last.flush
    expect(JSON.parse(report.first.read_nonblock(100_000))).to(include("counts"))
    expect(diagnostics.first.read_nonblock(100_000)).to(end_with("later"))
  end

  def noisy(stdout)
    harness = FakeHarness.new { stdout.write("noise") && Kimera::RunReport.new(results: []) }
    run = described_class.new(io: stdout, errors: $stderr, bench: FakeBench.new(harness: harness))
    project { run.run(%w[calc.rb --format json]) }
  end

  def detached_writes
    stdout = report.last
    stdout.sync = false
    stdout.write("early,")
    noisy(stdout)
    stdout.flush
    [report.first.read_nonblock(100_000), diagnostics.first.read_nonblock(100_000)]
  end

  it "keeps stdout for the report and sends everything else to stderr", :aggregate_failures do
    written, said = detached_writes
    expect(written).to(start_with("early,{"))
    expect(said).to(include("noise"))
  end
end
