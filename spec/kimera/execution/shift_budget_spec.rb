# frozen_string_literal: true

require "json"
require "kimera/execution/shift"
require "kimera/frameworks/adapter"
require "kimera/registry/builder"
require "stringio"

# A covering test that passes but runs past its relative budget (baseline ×
# factor + slack) makes the mutant a timeout, once the same test ran within
# budget with the mutant switched off and past it again with it on. A single
# slow run (a fresh worker's first test, a GC pause) is not a verdict.
RSpec.describe(Kimera::Execution::Shift) do
  let(:registry) do
    Kimera::RegistryScan.new.source(<<~RUBY, file: "calc.rb")
      def a(x, y)
        x > y
      end
    RUBY
  end

  let(:target) { registry.each.first.first.id }
  let(:clock) { [0.0] }
  let(:budget) { Kimera::Execution::TimeBudget.new({ "t1" => 0.01, "t2" => 0.01 }, factor: 10.0, slack: 1.0) }

  before { stub_const("Kimera::Execution::Shift::Deadline::CLOCK", -> { clock.first }) }

  after { Kimera::Runtime.reset! }

  # +script+ maps a test to its successive runs, as [seconds, passed?]
  # pairs; each run advances the fake clock. Unscripted runs are instant passes.
  def timed(script)
    now = clock
    Class.new do
      attr_reader :log

      define_method(:initialize) do
        @script = script.transform_values(&:dup)
        @log = []
      end

      define_method(:run) do |ids|
        id = ids.first
        @log << [id, Kimera::Runtime.active]
        took, passed = @script.fetch(id, []).shift || [0.0, true]
        now[0] += took
        Kimera::Frameworks::RunOutcome.new(passed: passed, failed_ids: passed ? [] : [id])
      end
    end.new
  end

  def worker(adapter, tests, **)
    described_class.new(
      adapter: adapter, registry: registry, coverage: { target => tests }, soft_timeout: 5.0, leak_every: 0,
      budget: budget, **
    )
  end

  def slow = [2.0, true]
  def fast = [0.01, true]

  it "is a timeout when a test overruns with the mutant on, then keeps to it off", :aggregate_failures do
    adapter = timed({ "t1" => [slow, fast, slow] })
    result = worker(adapter, %w[t1 t2]).evaluate(target)

    expect(result.status).to(eq(:timeout))
    expect(result.detail).to(
      eq(
        "t1 ran past its relative time budget with the mutant on (2.0s, then 2.0s; budget 1.1s = " \
          "baseline 0.01s × 10.0 + 1.0s), and in 0.01s with it off"
      )
    )
    expect(adapter.log).to(eq([["t1", target], ["t1", nil], ["t1", target]]))
  end

  it "reports the time the mutant took and the tests that cover it", :aggregate_failures do
    result = worker(timed({ "t1" => [slow, fast, slow] }), %w[t1 t2]).evaluate(target)
    expect(result.duration).to(be_positive)
    expect(result.covering_tests).to(eq(%w[t1 t2]))
  end

  it "counts as detected" do
    expect(worker(timed({ "t1" => [slow, fast, slow] }), %w[t1]).evaluate(target)).to(be_killed)
  end

  it "runs a test within its budget once, and goes on to the next", :aggregate_failures do
    adapter = timed({ "t1" => [[1.1, true]] })
    expect(worker(adapter, %w[t1 t2]).evaluate(target).status).to(eq(:survived))
    expect(adapter.log).to(eq([["t1", target], ["t2", target]]))
  end

  it "lets the budget go when the test overruns with the mutant off too", :aggregate_failures do
    adapter = timed({ "t1" => [slow, slow] })
    expect(worker(adapter, %w[t1 t2]).evaluate(target).status).to(eq(:survived))
    expect(adapter.log).to(eq([["t1", target], ["t1", nil], ["t2", target]]))
  end

  it "lets the budget go when the test fails with the mutant off", :aggregate_failures do
    adapter = timed({ "t1" => [slow, [0.01, false]] })
    expect(worker(adapter, %w[t1 t2]).evaluate(target).status).to(eq(:survived))
    expect(adapter.log).to(eq([["t1", target], ["t1", nil], ["t2", target]]))
  end

  it "lets a single slow run go when the rerun with the mutant on keeps to the budget", :aggregate_failures do
    adapter = timed({ "t1" => [slow, fast, fast] })
    expect(worker(adapter, %w[t1 t2]).evaluate(target).status).to(eq(:survived))
    expect(adapter.log).to(eq([["t1", target], ["t1", nil], ["t1", target], ["t2", target]]))
  end

  it "still kills on a failing test, however slow" do
    adapter = timed({ "t1" => [[2.0, false], fast, [2.0, false]] })
    expect(worker(adapter, %w[t1]).evaluate(target).status).to(eq(:killed))
  end

  it "keeps the old behavior for a test with no baseline" do
    adapter = timed({ "t3" => [slow] })
    expect(worker(adapter, %w[t3]).evaluate(target).status).to(eq(:survived))
  end

  it "keeps the old behavior without a budget" do
    adapter = timed({ "t1" => [slow] })
    shift = described_class.new(
      adapter: adapter, registry: registry, coverage: { target => %w[t1] }, soft_timeout: 5.0, leak_every: 0
    )
    expect(shift.evaluate(target).status).to(eq(:survived))
  end

  it "settles a recheck on a fresh worker too" do
    request = StringIO.new("#{JSON.generate(id: target, recheck: true)}\n")
    response = StringIO.new
    worker(timed({ "t1" => [slow, fast, slow] }), %w[t1]).serve(request, response)
    expect(JSON.parse(response.string.lines.first)).to(include("status" => "timeout"))
  end
end
