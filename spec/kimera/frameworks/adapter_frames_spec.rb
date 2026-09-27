# frozen_string_literal: true

require "kimera/frameworks/adapter"

# A failure message carries the first frames of the failing test, so a warm
# kill's detail says where it failed, not just that it did.
RSpec.describe(Kimera::Frameworks::Adapter) do
  let(:adapter) { described_class.new }

  def frames(backtrace) = adapter.__send__(:frames, backtrace)

  it "keeps the frames above Kimera's runner, and no more than five", :aggregate_failures do
    own = Array.new(7) { |i| "test/x_test.rb:#{i}:in 'x'" }
    runner = "#{described_class::HARNESS}/frameworks/minitest_adapter.rb:1:in 'run'"

    expect(frames(own.first(2) + [runner] + own)).to(eq(own.first(2)))
    expect(frames(own)).to(eq(own.first(5)))
    expect(frames(nil)).to(eq([]))
  end

  it "roots the harness at Kimera's lib directory" do
    expect(described_class::HARNESS).to(eq(File.expand_path("../../../lib/kimera", __dir__)))
  end
end
