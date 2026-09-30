# frozen_string_literal: true

require "open3"

RSpec.describe("machine-readable stdout") do
  # SimpleCov and Coveralls print from an at_exit hook, after kimera has written
  # its report; thor's suite made `--format json` unparseable that way.
  def write(fixture)
    FileUtils.mkdir_p(File.join(fixture, "app"))
    FileUtils.mkdir_p(File.join(fixture, "spec"))
    File.write(File.join(fixture, "app", "gate.rb"), "class Gate\n  def open?(n) = n > 0\nend\n")
    File.write(File.join(fixture, "spec", "gate_spec.rb"), <<~RUBY)
      require_relative "../app/gate"
      puts "LOAD_" + "NOISE"
      at_exit { puts "AT_EXIT_" + "NOISE" }
      RSpec.describe(Gate) { it { expect(Gate.new.open?(1)).to be(true) } }
    RUBY
  end

  def command(format, extra)
    [
      "bundle", "exec", "ruby", "-I", File.join(test_repo_root, "lib"), File.join(test_repo_root, "exe", "kimera"),
      "run", "app", "--tests", "spec/**/*_spec.rb", "--format", format, *extra
    ]
  end

  # Open3 hands kimera pipes, not a tty: the CI case.
  def run_with(format, *extra)
    Dir.mktmpdir("kimera-machine-stdout") do |fixture|
      write(fixture)
      env = { "BUNDLE_GEMFILE" => File.join(test_repo_root, "Gemfile") }
      Open3.capture3(env, *command(format, extra), chdir: fixture)
    end
  end

  it "keeps the suite's own output off stdout under --format json", :aggregate_failures do
    report, diagnostics, = run_with("json")
    expect(JSON.parse(report)["counts"]["total"]).to(be_positive)
    expect(diagnostics).to(include("LOAD_NOISE", "AT_EXIT_NOISE"))
  end

  it "writes plain progress lines to stderr only, for every machine format", :aggregate_failures do
    { "json" => /\A\{/, "sarif" => /\A\{/, "github" => /\A::/ }.each do |format, shape|
      report, diagnostics, = run_with(format)
      expect(report).to(match(shape))
      expect(report).not_to(include("kimera: "))
      expect(diagnostics).to(include("kimera: baseline 0/1 0%", "kimera: mutants 0/"))
      expect(diagnostics).to(match(%r{^kimera: mutants (\d+)/\1 100%  killed=\d+}))
      expect(diagnostics).not_to(include("\r"))
    end
  end

  it "prints no progress under --no-progress" do
    _report, diagnostics, = run_with("json", "--no-progress")
    expect(diagnostics).not_to(match(/^kimera: (baseline|mutants)/))
  end
end
