# frozen_string_literal: true

RSpec.describe("kimera run --test-quality (end-to-end)", :aggregate_failures) do
  def app(name) = File.join(test_repository_root, "examples", name)

  # A plain run and a --test-quality run of the same suite.
  def both(cwd, tests, arguments = [])
    [[], ["--test-quality"]].map { |flags| test_outcome(cwd: cwd, tests: tests, arguments: arguments + flags) }
  end

  def keyed(run) = run.results.to_h { |row| [row["key"], row["status"]] }

  # What --test-quality names per mutant: killed rows whose failing tests it
  # leaves unnamed, the most killers of one mutant, and rows it names killers
  # for though nothing killed them.
  def quality_facts(run)
    killed, others = run.results.partition { |row| row["status"] == "killed" }
    {
      unnamed: killed.reject { |row| (row["failing_tests"] - row["killing_tests"]).empty? },
      most: killed.map { |row| row["killing_tests"].size }.max,
      stray: others.select { |row| row.key?("killing_tests") }
    }
  end

  def summary = include("tests" => 10, "kills_nothing" => [], "covers_nothing" => [])

  it "names every test that kills each mutant on RSpec, judging every mutant as a plain run does" do
    plain, quality = both(app("sample_app"), "spec/**/*_spec.rb")
    expect(quality_facts(quality)).to(match(unnamed: [], most: be > 1, stray: []), quality.output)
    expect(quality.report).to(include("test_quality" => summary, "run" => include("test_quality" => true)))
    expect(quality.output).to(include("Test quality (10 tests):"))
    expect(keyed(quality)).to(eq(keyed(plain)))
  end

  it "names every test that kills each mutant on Minitest, judging every mutant as a plain run does" do
    plain, quality = both(app("minitest_app"), "test/**/*_test.rb", ["--framework", "minitest"])
    expect(quality.results.select { |row| row["status"] == "killed" }).to(all(include("killing_tests")))
    expect(keyed(quality)).to(eq(keyed(plain)).and(be_any), quality.output)
  end
end
