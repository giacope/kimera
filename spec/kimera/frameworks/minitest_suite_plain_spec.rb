# frozen_string_literal: true

require "kimera/frameworks/minitest_suite"

RSpec.describe(Kimera::Frameworks::MinitestSuite, :aggregate_failures) do
  describe "rerunning baseline failures without kimera" do
    let(:selection) { described_class::Selection.new([], {}, nil) }

    def reproducing(*ids)
      Class.new(described_class::Selection) { def to_s = "bundle exec ruby -e 1 #{@ids.join(" ")}" }.new(ids, {}, nil)
    end

    it "reruns through its reproduce command in a shell" do
      expect(reproducing("CalcTest#test_a").plain("/ignored"))
        .to(eq(["sh", "-c", "bundle exec ruby -e 1 CalcTest#test_a"]))
    end

    it "reads the failures and errors Minitest printed" do
      output = "  1) Failure:\nCalcTest#test_a [test/calc_test.rb:3]:\nExpected 1\n\n  " \
        "2) Error:\nCalcTest#test_b:\nRuntimeError: boom\n"
      expect(selection.failed(output, nil)).to(eq(%w[CalcTest#test_a CalcTest#test_b]))
    end
  end
end
