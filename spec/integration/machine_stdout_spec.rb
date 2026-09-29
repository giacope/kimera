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

  def command(format)
    [
      "bundle", "exec", "ruby", "-I", File.join(test_repo_root, "lib"), File.join(test_repo_root, "exe", "kimera"),
      "run", "app", "--tests", "spec/**/*_spec.rb", "--format", format
    ]
  end

  def run_with(format)
    Dir.mktmpdir("kimera-machine-stdout") do |fixture|
      write(fixture)
      Open3.capture3({ "BUNDLE_GEMFILE" => File.join(test_repo_root, "Gemfile") }, *command(format), chdir: fixture)
    end
  end

  it "keeps the suite's own output off stdout under --format json", :aggregate_failures do
    report, diagnostics, = run_with("json")
    expect(JSON.parse(report)["counts"]["total"]).to(be_positive)
    expect(diagnostics).to(include("LOAD_NOISE", "AT_EXIT_NOISE"))
  end
end
