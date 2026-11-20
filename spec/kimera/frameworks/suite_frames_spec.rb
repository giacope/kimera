# frozen_string_literal: true

require "kimera/frameworks/suite"

RSpec.describe(Kimera::Frameworks::Suite) do
  let(:adapter) { Class.new(described_class) { def run(backtrace) = frames(backtrace) }.new }

  def frames(backtrace) = adapter.run(backtrace)

  it "keeps the frames above Kimera's runner, and no more than five", :aggregate_failures do
    own = Array.new(7) { |i| "test/x_test.rb:#{i}:in 'x'" }
    runner = "#{described_class::HARNESS}/frameworks/minitest_suite.rb:1:in 'run'"

    expect(frames(own.first(2) + [runner] + own)).to(eq(own.first(2)))
    expect(frames(own)).to(eq(own.first(5)))
    expect(frames(nil)).to(eq([]))
  end

  it "roots the harness at Kimera's lib directory" do
    expect(described_class::HARNESS).to(eq(File.expand_path("../../../lib/kimera", __dir__)))
  end
end
