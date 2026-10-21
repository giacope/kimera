# frozen_string_literal: true

require "kimera/registry/mutation_point"

RSpec.describe(Kimera::MutationPoint) do
  def sample
    described_class.new(
      point_id: 1, file: "a.rb", operator: "comparison", node_type: "call_node",
      location: Kimera::Location.new(
        start_offset: 0, span: 3, start_line: 1,
        start_column: 0, end_line: 1, end_column: 3
      ),
      original_source: "a > b",
      method_name: "compare",
      mutants: [Kimera::Mutant.new(id: 2, label: "> => <", directive: { "type" => "comparison" })]
    )
  end

  def matcher
    have_attributes(
      point_id: 1, file: "a.rb", operator: "comparison", node_type: "call_node",
      original_source: "a > b", method_name: "compare", safe?: true
    )
  end

  it "round-trips every field (including nested location and mutants)", :aggregate_failures do
    reloaded = described_class.from_h(sample.to_h)
    expect(reloaded).to(matcher)
    expect(reloaded.location.to_h).to(eq(sample.location.to_h))
    expect(reloaded.mutants.map(&:to_h)).to(eq(sample.mutants.map(&:to_h)))
  end

  def keys
    %w[point_id file operator node_type location original_source method_name schema_safe unsafe_reason mutants]
  end

  it "serializes each field under its own key", :aggregate_failures do
    h = sample.to_h
    expect(h.keys).to(match_array(keys))
    expect(h["location"]).to(eq(sample.location.to_h))
    expect(h["mutants"]).to(eq(sample.mutants.map(&:to_h)))
  end

  it "defaults schema_safe to true when the key is absent (older registries)" do
    h = sample.to_h
    h.delete("schema_safe")
    expect(described_class.from_h(h).safe?).to(be(true))
  end

  def unsafe
    point = sample
    point.unsafe!(described_class::CLASS_BODY_REASON)
    point
  end

  it "carries the class-body unsafe reason through the round-trip" do
    reloaded = described_class.from_h(unsafe.to_h)
    expect(reloaded).to(have_attributes(safe?: false, unsafe_reason: described_class::CLASS_BODY_REASON, body?: true))
  end
end
