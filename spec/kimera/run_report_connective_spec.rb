# frozen_string_literal: true

require "kimera/registry/builder"
require "kimera/results/run_report"

# liquid's `left && right && left.respond_to?(...)`: kimera swaps the inner
# `left && right` as one node, so pasting `left || right` by hand checked a
# different mutant (`left || (right && ...)`).
RSpec.describe(Kimera::RunReport, :aggregate_failures) do
  let(:registry) do
    Kimera::RegistryScan.new.source(
      "def ok?(a, b, c)\n  a && b && c\nend\n\ndef big?(a)\n  a > 1\nend\n",
      file: "cond.rb"
    )
  end

  def row(label)
    mutant = registry.each.find { |found, _point| found.label == label }.first
    result = Kimera::MutantResult.new(mutant_id: mutant.id, status: :survived, file: "cond.rb")
    described_class.new(results: [result], registry: registry).to_h["results"].first
  end

  it "shows a swapped connective in parentheses, as kimera mutated it" do
    swapped = registry.each.map { |found, _point| found.label }.grep(/&& => \|\|/)
    expect(swapped).not_to(be_empty)
    expect(swapped.map { |label| row(label)["mutated"] }).to(all(start_with("(").and(end_with(")"))))
  end

  it "leaves other replacements as they are" do
    other = registry.each.map { |found, _point| found.label }.grep_v(/&& => \|\|/).first
    expect(row(other)["mutated"]).not_to(start_with("("))
  end
end
