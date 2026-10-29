# frozen_string_literal: true

require "kimera/operators"
require "kimera/registry/builder"
require "kimera/synthesis/guard_splice"
require "kimera/synthesis/source_map"

RSpec.describe(Kimera::GuardSplice) do
  let(:source) { "def a(x) = x > 1\ndef b(y) = y < 2\n" }
  let(:map) { Kimera::SourceMap.new(source) }
  let(:points) do
    comparisons = Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: %w[comparison]))
    comparisons.source(source, file: "x.rb").points
  end

  # An index that finds the node of the first point only, as when a later point's node is gone.
  def first_only(index)
    first = points.first
    Class.new { define_method(:anchored) { |point| point.equal?(first) ? index.anchored(point) : [] } }.new
  end

  it "applies the mutants of the points it placed and leaves the rest", :aggregate_failures do
    index = Kimera::SpliceIndex.new(map.ast)
    splice = described_class.new(map, points, index: first_only(index), sites: Kimera::GuardSite.new(index))
    expect(splice.applied).to(eq(points.first.ids))
    expect(splice.rest).to(eq([points.last]))
  end
end
