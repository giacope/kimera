# frozen_string_literal: true

require "kimera/cli/run"
require "kimera/registry/builder"

RSpec.describe(Kimera::CLI::Run::Route) do
  let(:registry) { Kimera::RegistryScan.new.source("def m(a, b)\n  a > b\nend\n", file: "app/x.rb") }
  let(:ids) { registry.each.map { |mutant, _point| mutant.id } }

  it "isolates the mutants a pool-unsafe test covers, reading coverage only for a pattern", :aggregate_failures do
    reads = 0
    coverage = -> { (reads += 1) && { ids.first => ["spec/acp/end_to_end_spec.rb[1:1]"] } }
    apart, together = described_class.new(registry, isolate_when_covered_by: ["end_to_end_spec"]).split(ids, &coverage)
    expect([apart, together, reads]).to(eq([[ids.first], ids.drop(1), ids.size]))
  end

  it "reads no coverage without a pattern" do
    expect { described_class.new(registry, {}).split(ids) { raise(ArgumentError, "coverage read without a pattern") } }
      .not_to(raise_error)
  end

  it "judges isolated-only mutants on incremental runs unless told otherwise", :aggregate_failures do
    expect(described_class.new(registry, since: "origin/main").judging?).to(be(true))
    expect(described_class.new(registry, {}).judging?).to(be(false))
    expect(described_class.new(registry, since: "origin/main", judge_isolated_only: false).judging?).to(be(false))
    expect(described_class.new(registry, judge_isolated_only: true).judging?).to(be(true))
  end

  it "confirms survivors on incremental runs unless told otherwise", :aggregate_failures do
    expect(described_class.new(registry, since: "origin/main").confirming?).to(be(true))
    expect(described_class.new(registry, {}).confirming?).to(be(false))
    expect(described_class.new(registry, since: "origin/main", confirm_survivors: false).confirming?).to(be(false))
    expect(described_class.new(registry, confirm_survivors: true).confirming?).to(be(true))
  end
end
