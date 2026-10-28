# frozen_string_literal: true

require "kimera/frameworks/class_hooks"
require "minitest"

# Kimera runs one test the way Minitest runs a class's tests: through the
# class's suite runner (Minitest 6's run_suite, Minitest 5's run), with the
# class-level hooks around it and the per-test runner a class may specialise.
RSpec.describe(Kimera::Frameworks::ClassHooks) do
  # Kimera seeds Minitest before it runs a test; its suite orders by the seed.
  around do |example|
    saved = Minitest.seed
    Minitest.seed ||= 1
    example.run
  ensure
    Minitest.seed = saved
  end

  # A test class that notes what ran: its tests, and around them its info
  # handler, as minitest-hooks' before(:all) and after(:all) run there.
  def noted(seen, &)
    Class.new(Minitest::Test) do
      define_singleton_method(:name) { "NotedTest" }
      define_singleton_method(:with_info_handler) do |reporter, &block|
        seen << :around
        super(reporter, &block)
      end
      define_method(:test_ok) { seen << :ok }
      define_method(:test_bad) { seen.push(:bad).then { flunk("bad") } }
      class_eval(&) if block_given?
    end
  end

  it "runs the one test it names inside its class's handler, and answers its result", :aggregate_failures do
    seen = []
    result = described_class.new(noted(seen)).test("test_ok")
    expect([result.passed?, result.name, seen]).to(eq([true, "test_ok", %i[around ok]]))
    expect(described_class.new(noted(seen)).test("test_bad").failures.first.message).to(eq("bad"))
  end

  it "answers nil for a test its class does not run" do
    expect(described_class.new(noted([])).test("test_ok_too")).to(be_nil)
  end

  # Minitest 6 runs each class's tests through run_suite (excon starts its
  # test servers there, R6B5-M3); a class with one is run through it.
  def suited(seen)
    noted(seen) do
      define_singleton_method(:run_suite) do |reporter, options = {}|
        seen << :suite
        run(reporter, filter: options.fetch(:include))
      end
    end
  end

  it "runs the test through its class's run_suite where Minitest has one (R6B5-M3)" do
    seen = []
    described_class.new(suited(seen)).test("test_ok")
    expect(seen).to(eq(%i[suite around ok]))
  end

  it "prepares the test once it runs, after the suite drew its order" do
    seen = []
    described_class.new(noted(seen)).test("test_ok") { seen << :prepared }
    expect(seen).to(eq(%i[around prepared ok]))
  end

  # A class that records a failed before_all through the reporter, as
  # minitest-hooks does, and then skips its tests; or a failed after_all.
  def hooked(before: false, after: false)
    noted([]) do
      define_singleton_method(:with_info_handler) do |reporter, &block|
        hook = ->(label) { reporter.record(Minitest::Result.from(new(label).tap { it.failures << Minitest::Assertion.new(label) })) }
        before ? hook.call("before_all") : block.call
        hook.call("after_all") if after
      end
    end
  end

  it "reports a failed class hook as the test's result", :aggregate_failures do
    expect(described_class.new(hooked(before: true)).test("test_ok").name).to(eq("before_all"))
    expect(described_class.new(hooked(after: true)).test("test_ok").name).to(eq("after_all"))
    expect(described_class.new(hooked(after: true)).test("test_bad").name).to(eq("test_bad"))
  end

  it "runs a test its class runs in parallel in place, and leaves the executor as it was", :aggregate_failures do
    seen = []
    executor = Minitest.parallel_executor
    parallel = described_class.new(noted(seen) { parallelize_me! })
    expect(parallel.test("test_ok") { seen << :prepared }&.passed?).to(be(true))
    expect([seen, Minitest.parallel_executor]).to(eq([%i[around prepared ok], executor]))
  end

  # Minitest's info handler asks the reporter whether it passed when it prints
  # results on SIGINFO, and for its reporters.
  it "hands the suite a reporter that has passed until a result fails", :aggregate_failures do
    reporter = described_class::Reporter.new([], proc {})
    passing = Minitest::Result.from(Minitest::Test.new("x"))
    expect([reporter.passed?, reporter.tap { it.record(passing) }.passed?, reporter.reporters]).to(eq([true, true, []]))
    reporter.record(Minitest::Result.from(Minitest::Test.new("y").tap { it.failures << Minitest::Assertion.new }))
    expect([reporter.passed?, reporter.synchronize { :held }]).to(eq([false, :held]))
  end
end
