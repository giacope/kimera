# frozen_string_literal: true

RSpec.describe("kimera run --isolated (end-to-end)") do
  # The sample's known boundary survivor is mutant 3.
  it "reproduces the fast-path verdicts with fully out-of-process evaluation", :aggregate_failures do
    run = test_outcome(cwd: test_sample, arguments: ["--isolated"])
    expect(run.counts.slice("total", "timeout", "error", "leaks"))
      .to(eq({ "total" => 28, "timeout" => 0, "error" => 0, "leaks" => 0 }), run.output)
    expect([run.counts["killed"], run.counts["survived"], run.verdicts[3], run.status])
      .to(match([be >= 8, be >= 1, "survived", 2]))
  end

  def minitest(*arguments)
    test_outcome(
      cwd: File.join(test_repository_root, "examples", "minitest_app"), tests: "test/**/*_test.rb",
      arguments: ["--framework", "minitest", *arguments]
    )
  end

  it "evaluates a minitest suite out of process (framework parity)" do
    warm = minitest.verdicts
    run = minitest("--isolated", "--jobs", "4")
    expect([run.verdicts, run.counts["error"], run.status]).to(eq([warm, 0, 2]), run.output)
  end

  it "reaches identical verdicts with parallel mirrors (--jobs 4)" do
    serial = test_outcome(cwd: test_sample, arguments: ["--isolated"]).verdicts
    run = test_outcome(cwd: test_sample, arguments: ["--isolated", "--jobs", "4"])
    expect([run.verdicts, run.status]).to(eq([serial, 2]), run.output)
  end

  # A suite that can't load in the mirror must stop the run, not score every
  # mutant it covers as killed.
  def test_unloadable(root)
    FileUtils.cp_r(File.join(test_repository_root, "examples", "minitest_app", "."), root)
    FileUtils.mkdir_p(File.join(root, "coverage"))
    test = File.join(root, "test", "scorer_test.rb")
    guard = %(raise ArgumentError, "needs coverage/" unless Dir.exist?(File.expand_path("../coverage", __dir__))\n)
    File.write(test, guard + File.read(test))
  end

  def unloadable
    Dir.mktmpdir("kimera-unloadable") do |root|
      test_unloadable(root)
      test_outcome(cwd: root, tests: "test/**/*_test.rb", arguments: ["--framework", "minitest", "--isolated"])
    end
  end

  it "aborts when the unmutated suite fails to load in the mirror, naming the error", :aggregate_failures do
    run = unloadable
    expect(run.output).to(include("isolated baseline is not green", "ArgumentError: needs coverage/"))
    expect([run.report, run.status]).to(eq([nil, 1]))
  end
end
