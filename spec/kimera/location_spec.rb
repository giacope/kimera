# frozen_string_literal: true

require "kimera/registry/mutation_point"

RSpec.describe(Kimera::Location) do
  def sample
    described_class.new(start_offset: 10, span: 5, start_line: 2, start_column: 4, end_line: 3, end_column: 6)
  end

  it "round-trips every field through to_h / from_h" do
    reloaded = described_class.from_h(sample.to_h)
    expect(reloaded).to(eq(sample))
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

  it "anchors a node of a type at its offsets" do
    expect(sample.anchor(:call_node)).to(eq([10, 15, :call_node]))
  end

  it "covers the offsets it spans, and starts between the bounds it is given", :aggregate_failures do
    expect([9, 10, 14, 15].map { sample.covers?(it) }).to(eq([false, true, true, false]))
    expect([[0, 9], [0, 10], [10, 20], [11, 20]].map { sample.starts_between?(*it) }).to(eq([false, true, true, false]))
  end

  it "starts on its line, at its offset and column counted from one", :aggregate_failures do
    expect([1, 2, 3].map { sample.starts_on?(it) }).to(eq([false, true, false]))
    expect([9, 10, 11].map { sample.starts_at?(it) }).to(eq([false, true, false]))
    expect([4, 5, 6].map { sample.column?(it) }).to(eq([false, true, false]))
  end

  it "prints itself as its line and column" do
    expect(sample.to_s).to(eq("2:5"))
  end

  it "tells whether some range holds it strictly inside", :aggregate_failures do
    span = Struct.new(:start_offset, :end_offset)
    expect(sample.within?([span.new(9, 15)])).to(be(true))
    expect(sample.within?([span.new(10, 15), span.new(9, 14)])).to(be(false))
  end

  it "builds from a prism location" do
    span = Data.define(:start_offset, :length, :start_line, :start_column, :end_line, :end_column)
    location = described_class.parse(span.new(10, 5, 2, 4, 3, 6))
    expect(location.to_h).to(eq(sample.to_h))
  end
end
