# frozen_string_literal: true

require "kimera/frameworks/class_hooks"
require "minitest"

RSpec.describe(Kimera::Frameworks::ClassHooks) do
  around do |example|
    saved = Minitest.seed
    Minitest.seed ||= 1
    example.run
  ensure
    Minitest.seed = saved
  end

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

  def asking(asked)
    noted([]) do
      define_singleton_method(:with_info_handler) do |reporter, &block|
        asked.push(reporter.passed?, reporter.reporters.grep(Minitest::SummaryReporter))
        block.call
        asked.push(reporter.passed?, reporter.synchronize { :held })
      end
    end
  end

  it "hands the suite a reporter that has passed until a result fails" do
    asked = []
    described_class.new(asking(asked)).test("test_bad")
    expect(asked).to(eq([true, [], false, :held]))
  end

  it "lets a test the transcript has not seen pass, and a passing or skipped one too", :aggregate_failures do
    transcript = described_class::Transcript.new(proc {})
    passing = Minitest::Result.from(Minitest::Test.new("x"))
    skipped = Minitest::Result.from(Minitest::Test.new("y").tap { it.failures << Minitest::Skip.new })
    expect([transcript.passed?, transcript.tap { it.record(passing) }.tap { it.record(skipped) }.passed?])
      .to(eq([true, true]))
  end
end
