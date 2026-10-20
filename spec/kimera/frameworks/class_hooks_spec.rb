# frozen_string_literal: true

require "kimera/frameworks/class_hooks"
require "minitest"

RSpec.describe(Kimera::Frameworks::ClassHooks) do
  def result(passed:, skipped: false)
    instance_double(Minitest::Result, passed?: passed, skipped?: skipped)
  end

  # A class whose info handler wraps the block in class-level hooks, as
  # minitest-hooks does: it records a failed before_all through the reporter
  # and then skips the tests, or records a failed after_all after them.
  def hooked(before: nil, after: nil, run: true)
    Class.new do
      define_singleton_method(:with_info_handler) do |reporter, &block|
        reporter.record(before) if before
        block.call if run && !before
        reporter.record(after) if after
      end
    end
  end

  it "returns the test's own result when the class hooks pass" do
    own = result(passed: false)
    expect(described_class.new(hooked).run { own }).to(be(own))
  end

  it "runs the test inside the class's info handler" do
    seen = []
    klass = Class.new { define_singleton_method(:with_info_handler) { |_, &block| block.call(seen << :around) } }
    described_class.new(klass).run { seen << :test }
    expect(seen).to(eq(%i[around test]))
  end

  it "reports a failed before_all as the test's result, the test never running" do
    failure = result(passed: false)
    ran = false
    outcome = described_class.new(hooked(before: failure)).run { ran = true }
    expect([outcome, ran]).to(eq([failure, false]))
  end

  it "reports a failed after_all over a passing test" do
    failure = result(passed: false)
    expect(described_class.new(hooked(after: failure)).run { result(passed: true) }).to(be(failure))
  end

  it "ignores hooks that passed or skipped", :aggregate_failures do
    own = result(passed: true)
    expect(described_class.new(hooked(after: result(passed: true))).run { own }).to(be(own))
    expect(described_class.new(hooked(after: result(passed: false, skipped: true))).run { own }).to(be(own))
  end

  it "runs one test by name inside the handler, as kimera's test runner extends it" do
    klass =
      Class.new do
        define_singleton_method(:with_info_handler) { |_, &block| block.call }
        define_method(:initialize) { |name| @name = name }
        define_method(:run) { [@name, singleton_class.include?(Kimera::TestExit::Test)] }
      end
    expect(described_class.new(klass).test("test_it")).to(eq(["test_it", true]))
  end

  it "answers nil when the handler never ran the test and nothing failed" do
    expect(described_class.new(hooked(run: false)).run { :never }).to(be_nil)
  end

  it "reports the reporter as passed until a hook fails", :aggregate_failures do
    hooks = described_class.new(hooked)
    expect(hooks.passed?).to(be(true))
    hooks.record(result(passed: false))
    expect(hooks.passed?).to(be(false))
  end
end
