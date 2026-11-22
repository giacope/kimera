# frozen_string_literal: true

require "kimera/execution/order_trace"
require "kimera/registry/builder"

using PointFields

RSpec.describe(Kimera::Execution::OrderTrace) do
  let(:registry) do
    Kimera::RegistryScan.new.source("def a(x, y)\n  x > y\nend\n\ndef b(x, y)\n  x < y\nend\n", file: "calc.rb")
  end

  let(:ids) { registry.each.map { |mutant, point| [mutant.to_i, point] }.uniq(&:last).map(&:first) }

  def reasons = registry.to_a.map { it.reasons(Kimera::Reason.revisiting).first }

  def ran(traces) = -> { traces }

  def marked(traces, coverage) = described_class.new(registry, nil).tap { it.mark!(ran(traces), coverage) }

  def traced(touches, coverage) = described_class.new(registry, suite(touches)).follow!(coverage)

  def suite(touches)
    Class.new(Kimera::Frameworks::Suite) do
      define_method(:test_ids) { touches.keys }
      define_method(:run) { |tests| touches.fetch(tests.first).each { Kimera::RUNTIME.active?(it) } }
    end.new
  end

  it "marks a point the run in order reached that no test covers" do
    first, last = ids
    marked({ "t1" => [first, last] }, { first => ["t1"], last.to_s => [] })
    expect(reasons).to(eq([nil, Kimera::Reason::ORDER_REASON]))
  end

  it "marks a point more tests reach in order than in a fresh process, and one no covering test reaches then" do
    first, last = ids
    marked({ "t1" => [first], "t2" => [first] }, { first => ["t1"], last => ["t1"] })
    expect(reasons).to(eq([Kimera::Reason::TRAIL_REASON, Kimera::Reason::MASK_REASON]))
  end

  it "leaves a point its covering tests still reach in order, or that order only hands to another test" do
    first, last = ids
    marked({ "t1" => [first], "t2" => [last, 999] }, { first.to_s => ["t1"], last => %w[t1 t3] })
    expect(reasons).to(eq([nil, nil]))
  end

  it "leaves a point that only the isolated tier judges" do
    registry.to_a.last.mark!(Kimera::Reason.unsafe("class body"))
    marked({ "t1" => [ids.last] }, {})
    expect(reasons.last).to(be_nil)
  end

  it "marks nothing when the run in order dies" do
    described_class.new(registry, nil).mark!(-> { raise(Kimera::Execution::Zygote::Died, "") }, { ids.last => ["t1"] })
    expect(reasons).to(eq([nil, nil]))
  end

  describe "#wanted?" do
    let(:mutants) { registry.to_a.map(&:ids) }

    def trace(timings = {}, jobs = 1) = described_class.new(registry, nil, timings:, jobs:)

    it "wants the run when no scope narrows it" do
      expect(trace.wanted?(nil, {})).to(be(true))
    end

    it "wants the run when a mutant in scope sits on a point with an uncovered mutant", :aggregate_failures do
      (covered, uncovered), = mutants
      coverage = { covered => ["t1"], uncovered.to_s => [] }
      expect(trace({ "t1" => 1.0, "t2" => 9.0 }).wanted?([covered], coverage)).to(be(true))
      expect(trace({ "t1" => 1.0, "t2" => 9.0 }).wanted?([covered], coverage.merge(uncovered => ["t1"]))).to(be(false))
    end

    it "wants the run when it costs no more than judging the mutants in scope on every worker", :aggregate_failures do
      first, = mutants
      coverage = first.to_h { |id| [id, ["t1"]] }
      timings = { "t1" => 1.0, "t2" => first.size - 1.0 }
      expect([1, 2].map { trace(timings, it).wanted?(first, coverage) }).to(eq([true, false]))
    end

    it "skips the run when every point in scope is covered, unsafe, or unknown, and the suite costs more" do
      first, second = mutants
      registry.to_a.last.mark!(Kimera::Reason.unsafe("class body"))
      coverage = first.to_h { |id| [id, ["t1"]] }
      costly = trace({ "t2" => 1.0 })
      expect([costly.wanted?(first + second, coverage), trace.wanted?([999], {}), trace.wanted?([], {})])
        .to(eq([false, false, false]))
    end
  end

  it "runs each test in order in one process beside the mutants, marking once it settles", :aggregate_failures do
    first, last = ids
    settle = traced({ "t1" => [first], "t2" => [first, last] }, { first => ["t1"] })
    expect(reasons).to(eq([nil, nil]))
    settle.call
    expect(reasons).to(eq([Kimera::Reason::TRAIL_REASON, Kimera::Reason::ORDER_REASON]))
  end

  it "starts nothing, and marks nothing when settled, when the run in order is not wanted" do
    every = registry.each.map { |mutant,| mutant.to_i }
    described_class.new(registry, nil, timings: { "t2" => 1.0 }).follow!(every.to_h { [it, ["t1"]] }, scope: every).call
    expect(reasons).to(eq([nil, nil]))
  end
end
