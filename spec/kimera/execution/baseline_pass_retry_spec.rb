# frozen_string_literal: true

require "kimera/execution/baseline_pass"
require "kimera/frameworks/adapter"
require "kimera/registry/builder"

# A baseline test whose worker hits the hard timeout under parallel load runs
# once more, alone, before it can turn the baseline red.
RSpec.describe(Kimera::Execution::BaselinePass) do
  let(:registry) do
    Kimera::RegistryScan.new.source(<<~RUBY, file: "calc.rb")
      def a(x, y)
        x > y
      end
    RUBY
  end

  let(:ids) { registry.each.map { |m, _p| m.id } }

  let(:adapter) do
    tests = %w[t1 t2 t3]
    Class.new(Kimera::Frameworks::Adapter) do
      define_method(:test_ids) { tests }
      define_method(:reproduce) { |failed| "rspec #{failed.join(" ")}" }
    end.new
  end

  def progress
    Class.new do
      attr_reader :ticks

      def initialize = @ticks = 0
      def start(*); end
      def finish; end
      def tick(*) = @ticks += 1
    end.new
  end

  def passed(id, touched = ids) = { "t" => "result", "id" => id, "passed" => true, "touched" => touched }

  def failed(id, touched = ids) = passed(id, touched).merge("passed" => false, "failure" => "boom in #{id}")

  # +first+ and +alone+ script the two rounds: each maps a test to :pass,
  # :fail, :timeout or :crash. Returns the pass's result and every round's
  # arguments.
  def measure(first, alone = {}, meter: progress)
    rounds = []
    pass = described_class.new(adapter: adapter, registry: registry, progress: meter)
    [pass.parallel! { |queue, jobs, **channels| round(queue, jobs, channels, [first, alone], rounds) }, rounds]
  end

  def round(queue, jobs, channels, scripts, rounds)
    script = scripts.fetch(rounds.size)
    rounds << { queue: queue, jobs: jobs, trace: channels[:trace] }
    queue.each { |id| play(id, script.fetch(id, :pass), channels[:resolve], channels[:lost]) }
  end

  def play(id, outcome, resolve, lost)
    case outcome
    when :pass then resolve.call(passed(id))
    when :fail then resolve.call(failed(id))
    when :stray then resolve.call(failed(id, []))
    when :timeout then lost.call(id, :timeout, "stacks of #{id}")
    when :crash then lost.call(id, :crash, nil)
    end
  end

  it "runs every test once, in parallel, when none stalls", :aggregate_failures do
    result, rounds = measure({})

    expect(rounds.size).to(eq(1))
    expect(rounds.first).to(include(queue: %w[t1 t2 t3], jobs: nil))
    expect(rounds.first[:trace]).to(respond_to(:call))
    expect(result.recovered).to(eq({}))
  end

  it "reruns only the tests that hit the hard timeout, alone and untraced", :aggregate_failures do
    _, rounds = measure({ "t1" => :timeout, "t3" => :timeout })
    expect(rounds.last).to(eq(queue: %w[t1 t3], jobs: 1, trace: nil))
  end

  it "keeps a test that passes alone, with its stacks, and its coverage", :aggregate_failures do
    result, = measure({ "t2" => :timeout })

    expect(result.recovered).to(eq("t2" => "stacks of t2"))
    expect(result.coverage[ids.first]).to(contain_exactly("t1", "t2", "t3"))
  end

  it "ticks each test once, however many rounds it takes", :aggregate_failures do
    meter = progress
    expect { measure({ "t1" => :timeout, "t2" => :crash }, { "t1" => :timeout }, meter: meter) }
      .to(raise_error(Kimera::Execution::BaselineFailure))
    expect(meter.ticks).to(eq(3))
  end

  it "fails the baseline when the test times out again alone, with the stacks of that run" do
    text = "  t1:\n    its worker was killed at the hard timeout (--hard-timeout) before reporting a result, " \
      "and again when rerun alone\n    stacks of t1\n"
    expect { measure({ "t1" => :timeout }, { "t1" => :timeout }) }
      .to(raise_error(Kimera::Execution::BaselineFailure, Regexp.new(Regexp.escape(text))))
  end

  it "keeps the stacks of the run that lost the test", :aggregate_failures do
    pass = described_class.new(adapter: adapter, registry: registry)
    pass.__send__(:lost, "t1", :timeout, "parallel stacks")
    pass.__send__(:relapse, "t1", :timeout, "stacks alone")
    pass.__send__(:relapse, "t2", :crash)
    expect(pass.__send__(:losses).stacks).to(eq("t1" => "stacks alone", "t2" => nil))
  end

  # A failure that covers no mutant in scope gates nothing, but didn't pass either.
  it "doesn't count a test that fails alone as recovered", :aggregate_failures do
    result, = measure({ "t1" => :timeout }, { "t1" => :stray })

    expect(result.recovered).to(eq({}))
    expect(result.irrelevant).to(eq(["t1"]))
  end

  it "fails the baseline on a test that fails when rerun alone", :aggregate_failures do
    expect { measure({ "t1" => :timeout }, { "t1" => :fail }) }.to(
      raise_error(Kimera::Execution::BaselineFailure, /baseline suite is not green: t1\n  t1:\n    boom in t1/)
    )
  end

  it "doesn't rerun a crash: it fails the baseline at once", :aggregate_failures do
    rounds = nil
    expect { _, rounds = measure({ "t3" => :crash }) }.to(
      raise_error(Kimera::Execution::BaselineFailure, /t3:\n    its worker died before reporting a result\n/)
    )
    expect(rounds).to(be_nil)
  end

  it "counts a crash as the parallel loss it was, not a rerun one" do
    pass = described_class.new(adapter: adapter, registry: registry)
    pass.__send__(:lost, "t1", :crash)
    expect(pass.instance_variable_get(:@messages)["t1"]).to(eq("its worker died before reporting a result"))
  end
end
