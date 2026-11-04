# frozen_string_literal: true

require "kimera/registry/mutation_point"

RSpec.describe(Kimera::Mutant) do
  def sample
    described_class.new(id: 7, label: "> => <", directive: { "type" => "comparison" })
  end

  it "round-trips every field through to_h / from_h", :aggregate_failures do
    reloaded = described_class.from_h(sample.to_h)
    expect(reloaded.to_i).to(eq(7))
    expect(reloaded.to_s).to(eq("> => <"))
    expect(reloaded.to_h.fetch("directive")).to(eq("type" => "comparison"))
  end

  it "serializes each field under its own key" do
    expect(sample.to_h).to(eq("id" => 7, "label" => "> => <", "directive" => { "type" => "comparison" }))
  end
end
