# frozen_string_literal: true

require "kimera/operators"
require "kimera/registry/builder"
require "kimera/synthesis/overlay"

# The overlay reads the mutants it applied off the woven tree: each appears
# once, whatever else the runtime is asked (a privatize registration).
RSpec.describe(Kimera::Overlay, :aggregate_failures) do
  it "names each applied mutant once, privatized ones too" do
    source = "class Shown\n  def shown(a) = a > 1\nend\n"
    registry = Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: %w[visibility comparison]))
      .source(source, file: "shown.rb")
    result = described_class.new(registry).synthesize("shown.rb", source)
    expect(result.mutant_ids.sort).to(eq(registry.each.map { |mutant, _point| mutant.id }.sort))
    expect(result.source).to(include("privatize"))
  end
end
