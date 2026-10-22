# frozen_string_literal: true

require "kimera/frameworks/minitest_suite"

# F9: a test red only under kimera is rerun outside it before kimera trusts it.
RSpec.describe(Kimera::Frameworks::MinitestSuite, :aggregate_failures) do
  describe "rerunning baseline failures without kimera" do
    let(:adapter) { described_class.allocate }

    it "reruns through its reproduce command in a shell" do
      allow(adapter).to(receive(:reproduce).with(["CalcTest#test_a"]).and_return("bundle exec ruby -e 1"))
      expect(adapter.plain(["CalcTest#test_a"], "/ignored")).to(eq(["sh", "-c", "bundle exec ruby -e 1"]))
    end

    it "reads the failures and errors Minitest printed" do
      output = "  1) Failure:\nCalcTest#test_a [test/calc_test.rb:3]:\nExpected 1\n\n  " \
        "2) Error:\nCalcTest#test_b:\nRuntimeError: boom\n"
      expect(adapter.failed_plainly(output, nil)).to(eq(%w[CalcTest#test_a CalcTest#test_b]))
    end
  end
end
