# frozen_string_literal: true

require "kimera/synthesis/guard_splice"

module OverlayFakes
  def unanchored
    nowhere = Class.new { def anchored(_point) = [] }.new
    unplaced = Class.new(Kimera::GuardSplice) { define_method(:initialize) { |map, points, **| super(map, points, index: nowhere) } }
    stub_const("Kimera::GuardSplice", unplaced)
  end

  def splicing(*written)
    stub_const("Kimera::BakeSplice", Class.new(Kimera::BakeSplice) { define_method(:source) { written } })
  end
end

RSpec.configure { |config| config.include(OverlayFakes) }
