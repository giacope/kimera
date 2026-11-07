# frozen_string_literal: true

require "delegate"
require "kimera/operators"
require "kimera/registry/builder"
require "kimera/synthesis/overlay"

using PointFields

RSpec.describe(Kimera::Overlay::MethodBake) do
  let(:source) { "def m(a) = a > 1\n" }
  let(:map) { Kimera::SourceMap.new(source) }
  let(:point) do
    comparisons = Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: %w[comparison]))
    comparisons.source(source, file: "x.rb").to_a.first
  end

  # A source map whose splices do not parse, as a graft that breaks the file around it.
  def unparseable(map) = Class.new(SimpleDelegator) { def splice(_edits) = "def (" }.new(map)

  it "grafts the method that holds the point into the file" do
    expect(described_class.new(map, map.ast).source(point)).to(eq(["def m(a); a > 1; end\n"]))
  end

  # Whether the file still parses is the bake's to judge (Overlay#checked refuses one that does not), not the graft's.
  it "grafts what the splice wrote, whether or not it parses" do
    expect(described_class.new(unparseable(map), map.ast).source(point)).to(eq(["def ("]))
  end
end
