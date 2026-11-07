# frozen_string_literal: true

require "delegate"
require "kimera/operators"
require "kimera/registry/builder"
require "kimera/synthesis/overlay"

RSpec.describe(Kimera::Overlay::MethodBake) do
  let(:source) { "def m(a) = a > 1\n" }
  let(:map) { Kimera::SourceMap.new(source) }
  let(:point) do
    comparisons = Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: %w[comparison]))
    comparisons.source(source, file: "x.rb").points.first
  end

  def unparseable(map) = Class.new(SimpleDelegator) { def splice(_edits) = "def (" }.new(map)

  it "grafts the method that holds the location into the file" do
    expect(described_class.new(map, map.ast).source(point.location)).to(eq(["def m(a); a > 1; end\n"]))
  end

  it "grafts what the splice wrote, whether or not it parses" do
    expect(described_class.new(unparseable(map), map.ast).source(point.location)).to(eq(["def ("]))
  end
end
