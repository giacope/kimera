# frozen_string_literal: true

RSpec.describe("kimera run --test-quality (end-to-end)", :aggregate_failures) do
  def verdicts(cwd, tests, arguments)
    test_run(cwd: cwd, tests: tests, arguments: arguments) do |output, report|
      expect(report).not_to(be_nil, "no report; output:\n#{output}")
      yield(report, output) if block_given?
      report["results"].to_h { |row| [row["key"], row["status"]] }
    end
  end

  def app(name) = File.join(test_repository_root, "examples", name)

  it "names every test that kills each mutant on RSpec, judging every mutant as a plain run does" do
    plain = verdicts(app("sample_app"), "spec/**/*_spec.rb", [])
    quality =
      verdicts(app("sample_app"), "spec/**/*_spec.rb", ["--test-quality"]) do |report, output|
        killed = report["results"].select { |row| row["status"] == "killed" }
        expect(killed).to(all(satisfy { |row| (row["failing_tests"] - row["killing_tests"]).empty? }))
        expect(killed.map { |row| row["killing_tests"].size }.max).to(be > 1)
        others = report["results"].reject { |row| row["status"] == "killed" }
        expect(others.select { |row| row.key?("killing_tests") }).to(be_empty)
        expect(report.fetch("test_quality")).to(include("tests" => 10, "kills_nothing" => [], "covers_nothing" => []))
        expect(report.dig("run", "test_quality")).to(be(true))
        expect(output).to(include("Test quality (10 tests):"))
      end
    expect(quality).to(eq(plain))
  end

  it "names every test that kills each mutant on Minitest, judging every mutant as a plain run does" do
    arguments = ["--framework", "minitest"]
    plain = verdicts(app("minitest_app"), "test/**/*_test.rb", arguments)
    quality =
      verdicts(app("minitest_app"), "test/**/*_test.rb", arguments + ["--test-quality"]) do |report|
        expect(report["results"].select { |row| row["status"] == "killed" }).to(all(include("killing_tests")))
      end
    expect(quality).to(eq(plain))
  end
end
