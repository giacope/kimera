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

  def ran(touched) = -> { { "touched" => touched } }

  it "marks a point the ordered run reached that no test covers" do
    first, last = ids
    described_class.new(registry).mark!(ran([first, last]), { first => ["t1"], last.to_s => [] })
    expect(reasons).to(eq([nil, Kimera::Reason::ORDER_REASON]))
  end

  it "leaves a point the ordered run did not reach, or a test covers" do
    first, last = ids
    described_class.new(registry).mark!(ran([first, 999]), { first.to_s => ["t1"], last => [] })
    expect(reasons).to(eq([nil, nil]))
  end

  it "leaves a point that only the isolated tier judges" do
    registry.to_a.last.mark!(Kimera::Reason.unsafe("class body"))
    described_class.new(registry).mark!(ran([ids.last]), {})
    expect(reasons.last).to(be_nil)
  end

  describe "#wanted?" do
    let(:trace) { described_class.new(registry) }
    let(:mutants) { registry.to_a.map(&:ids) }

    it "wants the run when no scope narrows it" do
      expect(trace.wanted?(nil, {})).to(be(true))
    end

    it "wants the run when a mutant in scope sits on a point with an uncovered mutant", :aggregate_failures do
      (covered, uncovered), = mutants
      coverage = { covered => ["t1"], uncovered.to_s => [] }
      expect(trace.wanted?([covered], coverage)).to(be(true))
      expect(trace.wanted?([covered], coverage.merge(uncovered => ["t1"]))).to(be(false))
    end

    it "skips the run when every point in scope is covered, unsafe, or unknown", :aggregate_failures do
      first, second = mutants
      registry.to_a.last.mark!(Kimera::Reason.unsafe("class body"))
      coverage = first.to_h { |id| [id, ["t1"]] }
      expect([trace.wanted?(first + second, coverage), trace.wanted?([999], {}), trace.wanted?([], {})])
        .to(eq([false, false, false]))
    end
  end

  it "starts the run in order, marking only once it is settled", :aggregate_failures do
    baseline = Struct.new(:touched) { def sequence(cell) = cell.call { { "touched" => touched } } }.new(ids)
    settle = described_class.new(registry).follow!(baseline, {})
    expect(reasons).to(eq([nil, nil]))
    settle.call
    expect(reasons).to(eq([Kimera::Reason::ORDER_REASON] * 2))
  end

  it "starts nothing, and marks nothing when settled, when no mutant in scope is uncovered" do
    every = registry.each.map { |mutant,| mutant.to_i }
    described_class.new(registry).follow!(nil, every.to_h { [it, ["t1"]] }, scope: every).call
    expect(reasons).to(eq([nil, nil]))
  end

  it "marks nothing when the run in order dies" do
    described_class.new(registry).mark!(-> { raise(Kimera::Execution::Zygote::Died, "") }, {})
    expect(reasons).to(eq([nil, nil]))
  end
end
