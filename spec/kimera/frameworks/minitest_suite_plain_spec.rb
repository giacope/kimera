# frozen_string_literal: true

require "kimera/frameworks/minitest_suite"

# F9: a test red only under kimera is rerun outside it before kimera trusts it.
RSpec.describe(Kimera::Frameworks::MinitestSuite, :aggregate_failures) do
  describe "rerunning baseline failures without kimera" do
    let(:adapter) { described_class.allocate }

    # A suite that reproduces each set of tests with a command naming them, past the loading this spec skips.
    def reproducing
      Class.new(described_class) { def reproduce(ids) = "bundle exec ruby -e 1 #{ids.join(" ")}" }.allocate
    end

    it "reruns through its reproduce command in a shell" do
      expect(reproducing.plain(["CalcTest#test_a"], "/ignored"))
        .to(eq(["sh", "-c", "bundle exec ruby -e 1 CalcTest#test_a"]))
    end

    it "reads the failures and errors Minitest printed" do
      output = "  1) Failure:\nCalcTest#test_a [test/calc_test.rb:3]:\nExpected 1\n\n  " \
        "2) Error:\nCalcTest#test_b:\nRuntimeError: boom\n"
      expect(adapter.failed_plainly(output, nil)).to(eq(%w[CalcTest#test_a CalcTest#test_b]))
    end
  end
end
