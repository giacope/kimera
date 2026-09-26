# frozen_string_literal: true

require "kimera/support/unparse"

# Minitest turns on deprecation warnings when it loads, and parser (under
# unparser) trips them on every synthesis, flooding the run's stderr.
RSpec.describe(Kimera::Unparse) do
  it "round-trips source without letting unparser's warnings through", :aggregate_failures do
    allow(Unparser).to(receive(:parse).and_wrap_original { |original, source| warn("noise") || original.call(source) })
    allow(Unparser).to(receive(:unparse).and_wrap_original { |original, node| warn("noise") || original.call(node) })
    expect { expect(described_class.unparse(described_class.parse("a > b"))).to(eq("a > b")) }.not_to(output.to_stderr)
  end
end
