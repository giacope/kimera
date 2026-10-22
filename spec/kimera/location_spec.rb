# frozen_string_literal: true

require "kimera/registry/mutation_point"

RSpec.describe(Kimera::Location) do
  def sample
    described_class.new(start_offset: 10, span: 5, start_line: 2, start_column: 4, end_line: 3, end_column: 6)
  end

  it "round-trips every field through to_h / from_h" do
    reloaded = described_class.from_h(sample.to_h)
    expect(reloaded).to(
      have_attributes(start_offset: 10, span: 5, start_line: 2, start_column: 4, end_line: 3, end_column: 6)
    )
  end

  def encoded
    {
      "start_offset" => 10, "length" => 5, "start_line" => 2,
      "start_column" => 4, "end_line" => 3, "end_column" => 6
    }
  end

  it "serializes each field under its own key" do
    expect(sample.to_h).to(eq(encoded))
  end

  it "derives finish from start_offset + length" do
    expect(sample.finish).to(eq(15))
  end

  it "spans an inclusive line range" do
    expect(sample.range).to(eq(2..3))
  end

  it "builds from a prism location" do
    prism = double(start_offset: 10, length: 5, start_line: 2, start_column: 4, end_line: 3, end_column: 6)
    location = described_class.parse(prism)
    expect(location.to_h).to(eq(sample.to_h))
  end
end
