# frozen_string_literal: true

require "kimera/cli/run"
require "stringio"
require "tmpdir"

RSpec.describe(Kimera::CLI::Run) do
  let(:report) { IO.pipe }
  let(:diagnostics) { IO.pipe }

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

  def machine?(*format, io: $stdout)
    project { cli(io: io).run(["calc.rb", "--no-report", *format]) }
    report.last.write("probe")
    report.last.flush
    diagnostics.first.read_nonblock(100_000, exception: false).to_s.end_with?("probe")
  end

  it "detaches stdout for a machine format written to the real stdout", :aggregate_failures do
    swapped do
      expect(machine?("--format", "text")).to(be(false))
      expect(machine?).to(be(false))
      expect(machine?("--format", "json")).to(be(true))
    end
  end

  it "leaves a report stream it was handed alone", :aggregate_failures do
    swapped do
      expect(machine?("--format", "json", io: StringIO.new)).to(be(false))
      expect(machine?("--format", "json", io: diagnostics.last)).to(be(false))
    end
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

  def later
    project { full("--format", "json") }
    report.last.write("later")
    report.last.flush
    [report.first.read_nonblock(100_000), diagnostics.first.read_nonblock(100_000)]
  end

  it "detaches stdout for the whole of a --format json run", :aggregate_failures do
    json, said = swapped { later }
    expect(JSON.parse(json)).to(include("counts"))
    expect(said).to(end_with("later"))
  end

  def noisy(stdout)
    harness = FakeHarness.new { stdout.write("noise") && Kimera::RunReport.new(results: []) }
    run = described_class.new(io: stdout, errors: $stderr, bench: FakeBench.new(harness: harness))
    project { run.run(%w[calc.rb --format json]) }
  end

  def writes
    stdout = report.last
    stdout.sync = false
    stdout.write("early,")
    noisy(stdout)
    stdout.flush
    [report.first.read_nonblock(100_000), diagnostics.first.read_nonblock(100_000)]
  end

  it "keeps stdout for the report and sends everything else to stderr", :aggregate_failures do
    written, said = swapped { writes }
    expect(written).to(start_with("early,{"))
    expect(said).to(include("noise"))
  end
end
