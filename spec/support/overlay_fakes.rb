# frozen_string_literal: true

require "kimera/synthesis/guard_splice"

# Stand-ins for the parts kimera writes an overlay with, each failing the
# way the real one can, in place of it for an example.
module OverlayFakes
  # A guard splice whose index anchors no point, so no guard holds in place
  # and every point is left for the definition written whole.
  def unanchored
    nowhere = Class.new { def anchored(_point) = [] }.new
    unplaced = Class.new(Kimera::GuardSplice) { define_method(:initialize) { |map, points, **| super(map, points, index: nowhere) } }
    stub_const("Kimera::GuardSplice", unplaced)
  end

  # A bake splice that writes +written+ (none: it cannot splice the bake).
  def splicing(*written)
    stub_const("Kimera::BakeSplice", Class.new(Kimera::BakeSplice) { define_method(:source) { written } })
  end
end

RSpec.configure { |config| config.include(OverlayFakes) }
