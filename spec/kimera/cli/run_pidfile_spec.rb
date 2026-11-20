# frozen_string_literal: true

require "kimera/cli/run"
require "stringio"
require "tmpdir"

RSpec.describe(Kimera::CLI::Run) do
  def inside
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        File.write("calc.rb", "def m(a, b)\n  a > b\nend\n")
        FileUtils.mkdir_p("spec")
        File.write("spec/calc_spec.rb", "")
        yield
      end
    end
  end

  def run(*argv, &)
    bench = FakeBench.new(harness: FakeHarness.new(&))
    outcome = described_class.new(io: StringIO.new, errors: StringIO.new, bench: bench).run(["calc.rb", *argv])
    ended(outcome, StringIO.new, StringIO.new)
  end

  def pid
    held = nil
    status =
      run("--pidfile", "kimera.pid") do
        held = File.read("kimera.pid")
        Kimera::RunReport.new(results: [])
      end
    [held, status]
  end

  it "holds the run's pid in the file while it runs, then removes it" do
    inside do
      expect([*pid, File.exist?("kimera.pid")]).to(eq(["#{Process.pid}\n", 0, false]))
    end
  end

  it "removes the file when the run stops on an error", :aggregate_failures do
    inside do
      expect(run("--pidfile", "kimera.pid", "--tests", "nope/*_spec.rb")).to(eq(1))
      expect(File).not_to(exist("kimera.pid"))
    end
  end

  it "removes the file when the run crashes", :aggregate_failures do
    inside do
      expect { run("--pidfile", "kimera.pid") { raise(ArgumentError, "boom") } }.to(raise_error(ArgumentError))
      expect(File).not_to(exist("kimera.pid"))
    end
  end

  def reported(*argv) = run(*argv) { Kimera::RunReport.new(results: []) }

  def saved
    reported
    JSON.parse(File.read("tmp/kimera/report.json"))
  end

  it "saves the JSON report to tmp/kimera/report.json unless told otherwise", :aggregate_failures do
    inside do
      expect(saved).to(include("schema_version" => 2))
      reported("--report", "elsewhere.json")
      expect(File).to(exist("elsewhere.json"))
    end
  end

  it "writes no file without --pidfile" do
    inside do
      reported("--no-report")
      expect(Dir.children(".").sort).to(eq(%w[calc.rb spec]))
    end
  end
end
