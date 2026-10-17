# frozen_string_literal: true

require "json"
require "kimera/cli"
require "kimera/cli/run"
require "kimera/registry/builder"
require "kimera/results/run_report"

# The report schema documents what `kimera run` writes for scripts and agents,
# so every key a report can carry must be described there, and no other.
RSpec.describe(Kimera::RunReport, :aggregate_failures) do
  let(:schema) { JSON.parse(File.read(File.expand_path("../../schema/report.schema.json", __dir__))) }
  let(:properties) { schema.fetch("properties") }
  let(:registry) { Kimera::RegistryScan.new.source("def gt(a, b)\n  a > b\nend\n", file: "cmp.rb") }
  let(:id) { registry.each.first.first.id }
  let(:document) do
    rich =
      result(:ignored, verdict: :killed, failing_tests: ["t1"], covering_tests: ["t1"], detail: "d", note: "n")
        .tap { |row| row.killing_tests = ["t1"] }
    report = described_class.new(results: [rich], registry: registry, tests: { "t1" => { "name" => "one" } })
    flake = { "test" => "t1", "failed_runs" => 1, "seeds" => [2], "failure" => "f" }
    flaky = { "runs" => 1, "seeds" => [2], "tests" => 1, "flaky" => [flake] }
    JSON.parse(JSON.generate(report.annotate(flaky: flaky, suite: ["t1"]).document("jobs" => 1)))
  end

  def result(status, **fields)
    Kimera::MutantResult.new(mutant_id: id, status: status, file: "cmp.rb", duration: 0.1, **fields)
  end

  it "names every top-level key a report holds" do
    expect(properties.keys).to(include(*document.keys))
    expect(schema.fetch("required")).to(all(satisfy { |key| document.key?(key) }))
  end

  it "names every count, and every status a count or result can hold" do
    statuses = (Kimera::Status::REPORTED + [:killed]).map(&:to_s)
    expect(properties.dig("counts", "properties").keys).to(match_array(document.fetch("counts").keys))
    expect(properties.dig("results", "items", "properties", "status", "enum")).to(match_array(statuses))
  end

  it "names every field of the flaky tests section" do
    section = properties.fetch("flaky_tests")
    expect(section.fetch("properties").keys).to(match_array(document.fetch("flaky_tests").keys))
    expect(section.dig("properties", "flaky", "items", "properties").keys)
      .to(match_array(document.dig("flaky_tests", "flaky", 0).keys))
  end

  it "names every field of the test quality section" do
    section = properties.fetch("test_quality").fetch("properties")
    expect(section.keys).to(match_array(document.fetch("test_quality").keys))
    killed = described_class.new(results: [result(:killed, covering_tests: ["t1"])]).annotate(suite: ["t1"])
    standing = JSON.parse(JSON.generate(killed.to_h)).dig("test_quality", "standings", "t1")
    expect(section.dig("standings", "additionalProperties", "properties").keys).to(match_array(standing.keys))
  end

  it "names every field of a fully enriched result" do
    fields = properties.dig("results", "items", "properties").keys
    expect(fields).to(include(*document.fetch("results").first.keys))
  end

  it "names every setting the run section records" do
    recorded = Kimera::CLI::Run::Cycle::SETTINGS.map(&:to_s) + %w[jobs since count_no_coverage narrowed]
    expect(properties.dig("run", "properties").keys).to(include(*recorded))
  end

  it "ships with the gem" do
    expect(Gem::Specification.load(File.expand_path("../../kimera.gemspec", __dir__)).files)
      .to(include("schema/report.schema.json"))
  end
end
