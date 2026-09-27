# frozen_string_literal: true

RSpec.describe("kimera run --isolated (end-to-end)") do
  it "reproduces the fast-path verdicts with fully out-of-process evaluation", :aggregate_failures do
    test_run(cwd: test_sample, args: ["--isolated"]) do |output, report, status|
      expect(report).not_to(be_nil, "no JSON report; output:\n#{output}")

      counts = report["counts"]
      expect(counts["total"]).to(eq(28))
      expect(counts["killed"]).to(be >= 8)
      expect(counts["survived"]).to(be >= 1)
      expect(counts["timeout"]).to(eq(0))
      expect(counts["error"]).to(eq(0))
      expect(counts["leaks"]).to(eq(0))
      # The sample's known boundary survivor.
      survivors = report["results"].select { |r| r["status"] == "survived" }
      expect(survivors.map { |r| r["mutant_id"] }).to(include(3))
      expect(status).to(eq(2))
    end
  end

  it "evaluates a minitest suite out of process (framework parity)", :aggregate_failures do
    minitest = File.join(test_repo_root, "examples", "minitest_app")

    warm = nil
    test_run(
      cwd: minitest, tests: "test/**/*_test.rb",
      args: ["--framework", "minitest"]
    ) do |_o, report, _s|
      warm = report["results"].to_h { |r| [r["mutant_id"], r["status"]] }
    end

    test_run(
      cwd: minitest, tests: "test/**/*_test.rb",
      args: ["--framework", "minitest", "--isolated", "--jobs", "4"]
    ) do |output, report, status|
      expect(report).not_to(be_nil, "no JSON report; output:\n#{output}")
      isolated = report["results"].to_h { |r| [r["mutant_id"], r["status"]] }
      expect(isolated).to(eq(warm))
      expect(report["counts"]["error"]).to(eq(0))
      expect(status).to(eq(2))
    end
  end

  it "reaches identical verdicts with parallel mirrors (--jobs 4)", :aggregate_failures do
    serial = nil
    test_run(cwd: test_sample, args: ["--isolated"]) do |_o, report, _s|
      serial = report["results"].to_h { |r| [r["mutant_id"], r["status"]] }
    end

    test_run(cwd: test_sample, args: ["--isolated", "--jobs", "4"]) do |output, report, status|
      expect(report).not_to(be_nil, "no JSON report; output:\n#{output}")
      parallel = report["results"].to_h { |r| [r["mutant_id"], r["status"]] }
      expect(parallel).to(eq(serial))
      expect(status).to(eq(2))
    end
  end

  # A suite that can't load in the mirror must stop the run, not score every
  # mutant it covers as killed.
  def test_unloadable(root)
    FileUtils.cp_r(File.join(test_repo_root, "examples", "minitest_app", "."), root)
    FileUtils.mkdir_p(File.join(root, "coverage"))
    test = File.join(root, "test", "scorer_test.rb")
    guard = %(raise ArgumentError, "needs coverage/" unless Dir.exist?(File.expand_path("../coverage", __dir__))\n)
    File.write(test, guard + File.read(test))
  end

  it "aborts when the unmutated suite fails to load in the mirror, naming the error", :aggregate_failures do
    Dir.mktmpdir("kimera-unloadable") do |root|
      test_unloadable(root)
      args = ["--framework", "minitest", "--isolated"]
      test_run(cwd: root, tests: "test/**/*_test.rb", args: args) do |output, report, status|
        expect(output).to(include("isolated baseline is not green", "ArgumentError: needs coverage/"))
        expect(report).to(be_nil)
        expect(status).to(eq(1))
      end
    end
  end
end
