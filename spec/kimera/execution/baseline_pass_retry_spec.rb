# frozen_string_literal: true

require "kimera/execution/baseline_pass"
require "kimera/frameworks/suite"
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
    Class.new(Kimera::Frameworks::Suite) do
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
  def measure(first, alone = {}, meter: progress, jobs: 1)
    rounds = []
    pass = described_class.new(adapter: adapter, registry: registry, progress: meter)
    [pass.parallel!(jobs) { |queue, jobs, listeners| round(queue, jobs, listeners, [first, alone], rounds) }, rounds]
  end

  def round(queue, jobs, listeners, scripts, rounds)
    script = scripts.fetch(rounds.size)
    rounds << { queue: queue, jobs: jobs, trace: listeners.trace }
    queue.each { |id| play(id, script.fetch(id, :pass), listeners.resolve, listeners.lost) }
  end

  def play(id, outcome, resolve, lost)
    case outcome
    when :pass then resolve.call(passed(id))
    when :fail then resolve.call(failed(id))
    when :stray then resolve.call(failed(id, []))
    when :timeout then lost.call(id, :timeout, "stacks of #{id}")
    when :crash then lost.call(id, :crash, nil)
    when :died then lost.call(id, :crash, "exited 1\nworker 0's after-fork setup raised RuntimeError: no index")
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
    expect(result.irrelevant.keys).to(eq(["t1"]))
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
    expect(pass.__send__(:tally).messages["t1"]).to(eq("its worker died before reporting a result"))
  end

  # A suite that shares a directory, file or port between tests is red on
  # several workers and green on one: the error says what to try.
  it "names --jobs 1 as the check when a baseline on several workers is red", :aggregate_failures do
    hint = "\n  ran on 3 workers: if the reproduce command above fails too, the tests are red on their own; if it " \
      "passes and --jobs 1 is green, the suite shares state between workers (a directory, file or port): use jobs: 1 " \
      "until each test has its own"
    expect { measure({ "t1" => :fail, "t2" => :fail }, jobs: 3) }.to(
      raise_error(Kimera::Execution::BaselineFailure) { |error| expect(error.message).to(end_with(hint)) }
    )
    expect { measure({ "t1" => :fail }) }.to(
      raise_error(Kimera::Execution::BaselineFailure) { |error| expect(error.message).not_to(include("--jobs 1")) }
    )
  end

  # Without coverage the baseline runs in one process, whatever --jobs says.
  it "doesn't name --jobs 1 for the baseline it checks in one process" do
    outcome = Struct.new(:passed?, :failures, :failed_ids).new(false, { "t1" => "boom" }, ["t1"])
    adapter.define_singleton_method(:run) { |_ids| outcome }
    pass = described_class.new(adapter: adapter, registry: registry)
    expect { pass.check!(InlineZygote.new) }.to(
      raise_error(
        Kimera::Execution::BaselineFailure,
        "baseline suite is not green: t1\n  t1:\n    boom\n  reproduce without kimera: rspec t1"
      )
    )
  end

  # R5-KW4: a red test that reached a mutant was "not green" though it passes plainly.
  def screening(passing)
    Class.new do
      attr_reader :screened

      define_method(:plainly!) do |failures|
        (@screened ||= []) << failures
        raise(Kimera::Execution::BaselineFailure, "harness error: #{failures.keys.join(" ")}") if passing
      end
    end.new
  end

  def screened(screen, first, check: false)
    allow(Kimera::Execution::BaselineScreen).to(
      receive(:new).with(
        adapter: adapter, root: "/app",
        jobs: 1
      ).and_return(screen)
    )
    pass = described_class.new(adapter: adapter, registry: registry, root: "/app")
    return pass.check!(InlineZygote.new) if check
    pass.parallel!(1) { |queue, _jobs, listeners| round(queue, nil, listeners, [first], []) }
  end

  it "stops with the harness error when the red tests pass plainly", :aggregate_failures do
    screen = screening(true)
    expect { screened(screen, { "t1" => :fail, "t3" => :crash }) }
      .to(raise_error(Kimera::Execution::BaselineFailure, "harness error: t1 t3"))
    expect(screen.screened).to(eq([{ "t1" => "boom in t1", "t3" => "its worker died before reporting a result" }]))
  end

  # R4-KR1: the harness error kept only "its worker died", not the after-fork hook's error.
  it "hands the screen what a lost test's worker left", :aggregate_failures do
    screen = screening(true)
    expect { screened(screen, { "t2" => :died }) }.to(raise_error(Kimera::Execution::BaselineFailure))
    left = "exited 1\nworker 0's after-fork setup raised RuntimeError: no index"
    expect(screen.screened).to(eq([{ "t2" => ["its worker died before reporting a result", left] }]))
  end

  it "calls the baseline not green when the red tests fail plainly too", :aggregate_failures do
    screen = screening(false)
    expect { screened(screen, { "t2" => :fail }) }
      .to(raise_error(Kimera::Execution::BaselineFailure, /\Abaseline suite is not green: t2/))
    expect(screen.screened).to(eq([{ "t2" => "boom in t2" }]))
  end

  it "screens the baseline it checks in one process too" do
    outcome = Struct.new(:passed?, :failures, :failed_ids).new(false, { "t1" => "boom" }, ["t1"])
    adapter.define_singleton_method(:run) { |_ids| outcome }
    expect { screened(screening(true), {}, check: true) }
      .to(raise_error(Kimera::Execution::BaselineFailure, "harness error: t1"))
  end

  it "screens nothing when it has no project root to rerun the tests in", :aggregate_failures do
    allow(Kimera::Execution::BaselineScreen).to(receive(:new))
    expect { measure({ "t1" => :fail }) }.to(raise_error(Kimera::Execution::BaselineFailure))
    expect(Kimera::Execution::BaselineScreen).not_to(have_received(:new))
  end

  it "screens nothing when the baseline is green" do
    screen = screening(true)
    screened(screen, {})
    expect(screen.screened).to(be_nil)
  end

  describe "the whole suite, run once in order" do
    include_context("with an inline zygote")

    def outcome(failed) = Kimera::Frameworks::RunOutcome.new(passed: failed.empty?, failed_ids: failed, failures: {})

    # +failed+ fail when the whole suite runs; a test run alone fails unless +alone+.
    def scripted(failed, touch: [], alone: false)
      whole = outcome(failed)
      lone = outcome(alone ? [] : ["t"])
      adapter.define_singleton_method(:run) do |ids|
        touch.each { |id| Kimera::RUNTIME.active?(id) }
        ids.size > 1 ? whole : lone
      end
    end

    def summary = Kimera::Execution::BaselineFailure::Summary

    # A suite that warns as it runs.
    def noisy
      quiet = outcome([])
      adapter.define_singleton_method(:run) do |_ids|
        warn("suite noise")
        quiet
      end
    end

    it "closes the ledger it opens" do
      scripted([])
      pass = described_class.new(adapter: adapter, registry: registry)
      expect { pass.sequence }.not_to(change(Kimera::RUNTIME, :leaks))
    end

    it "keeps the suite's own output off the terminal" do
      noisy
      expect { described_class.new(adapter: adapter, registry: registry).sequence }.not_to(output.to_stderr)
    end

    # Under a run of kimera on itself the outer run's guards fire too.
    it "reports which mutants it reached" do
      scripted([], touch: [ids.first, ids.first])
      touched = described_class.new(adapter: adapter, registry: registry).sequence["touched"]
      expect(touched.intersection(ids)).to(eq([ids.first]))
    end

    it "names the failing tests that pass when the suite runs in order", :aggregate_failures do
      scripted(["t2"])
      expect { measure({ "t1" => :fail, "t2" => :fail }) }.to(
        raise_error(Kimera::Execution::BaselineFailure) do |error|
          expect(error.message).to(include("not green").and(end_with("#{summary::ORDERED}\n    t1")))
        end
      )
    end

    it "calls the suite order-dependent when it is green in order" do
      scripted([])
      expect { measure({ "t1" => :fail }) }
        .to(raise_error(Kimera::Execution::BaselineFailure, /\Abaseline suite is order-dependent: t1/))
    end

    it "names none when the failing tests pass alone too: they share something across workers" do
      scripted([], alone: true)
      expect { measure({ "t1" => :fail }, jobs: 2) }.to(
        raise_error(Kimera::Execution::BaselineFailure, /\Abaseline suite is not green: t1.*ran on 2 workers/m)
      )
    end

    it "names none when the run in order can't finish", :aggregate_failures do
      adapter.define_singleton_method(:run) { |_ids| raise(ArgumentError, "broken") }
      expect { measure({ "t1" => :fail }) }.to(
        raise_error(Kimera::Execution::BaselineFailure) { |error| expect(error.message).not_to(include(summary::ORDERED)) }
      )
    end
  end
end
