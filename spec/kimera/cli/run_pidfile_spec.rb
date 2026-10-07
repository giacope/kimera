# frozen_string_literal: true

require "kimera/cli/run"
require "stringio"
require "tmpdir"

# --pidfile gives a script kimera's own pid to wait on; `pgrep -f "kimera
# run"` also matches the shell that launched it.
RSpec.describe(Kimera::CLI::Run) do
  around do |example|
    Dir.mktmpdir { |dir| Dir.chdir(dir) { example.run } }
  end

  before do
    File.write("calc.rb", "def m(a, b)\n  a > b\nend\n")
    FileUtils.mkdir_p("spec")
    File.write("spec/calc_spec.rb", "")
  end

  def run(*argv, &)
    allow(Kimera::Execution::Harness).to(receive(:build).and_wrap_original) do |original, **kwargs|
      original.call(**kwargs).tap do |harness|
        allow(harness).to(receive(:warm!))
        allow(harness).to(receive(:run, &))
      end
    end
    described_class.new(io: StringIO.new, errors: StringIO.new).run(["calc.rb", *argv])
  end

  it "holds the run's pid in the file while it runs, then removes it", :aggregate_failures do
    held = nil
    status =
      run("--pidfile", "kimera.pid") do
        held = File.read("kimera.pid")
        Kimera::RunReport.new(results: [])
      end
    expect(held).to(eq("#{Process.pid}\n"))
    expect(status).to(eq(0))
    expect(File).not_to(exist("kimera.pid"))
  end

  it "removes the file when the run stops on an error", :aggregate_failures do
    expect(run("--pidfile", "kimera.pid", "--tests", "nope/*_spec.rb")).to(eq(1))
    expect(File).not_to(exist("kimera.pid"))
  end

  it "removes the file when the run crashes", :aggregate_failures do
    expect { run("--pidfile", "kimera.pid") { raise(ArgumentError, "boom") } }.to(raise_error(ArgumentError))
    expect(File).not_to(exist("kimera.pid"))
  end

  it "saves the JSON report to tmp/kimera/report.json unless told otherwise", :aggregate_failures do
    run { Kimera::RunReport.new(results: []) }
    expect(JSON.parse(File.read("tmp/kimera/report.json"))).to(include("schema_version" => 1))
    run("--report", "elsewhere.json") { Kimera::RunReport.new(results: []) }
    expect(File).to(exist("elsewhere.json"))
  end

  it "writes no file without --pidfile" do
    run("--no-report") { Kimera::RunReport.new(results: []) }
    expect(Dir.children(".").sort).to(eq(%w[calc.rb spec]))
  end
end
