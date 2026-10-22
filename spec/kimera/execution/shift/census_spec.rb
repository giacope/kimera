# frozen_string_literal: true

require "json"
require "kimera/execution/shift"
require "kimera/frameworks/suite"
require "kimera/registry/builder"
require "stringio"

# Each covering test runs alone, in a fresh zygote, with the mutant on.
RSpec.describe(Kimera::Execution::Shift::Census) do
  let(:registry) { Kimera::RegistryScan.new.source("def a(x, y)\n  x > y\nend\n", file: "calc.rb") }
  let(:target) { registry.each.first.first.id }

  # t1 and t2 fail with the mutant on; t3 passes; "raise" errors, "hang" sleeps past the soft timeout.
  def adapter(runs = [])
    Class.new(Kimera::Frameworks::Suite) do
      define_method(:test_ids) { %w[t1 t2 t3 raise hang] }
      define_method(:run) do |ids|
        runs << [Kimera::RUNTIME.active, ids]
        raise(ArgumentError, "boom") if ids == ["raise"]
        sleep(1) if ids == ["hang"]
        failed = ids & %w[t1 t2]
        Kimera::Frameworks::RunOutcome.new(passed: failed.empty?, failed_ids: failed)
      end
    end.new
  end

  def shift(adapter, quality: true, zygote: InlineZygote.new)
    Kimera::Execution::Shift.new(
      adapter: adapter, registry: registry, coverage: { target => %w[t1 t2 t3 raise hang] },
      soft_timeout: 0.2, zygote: zygote, quality: quality
    )
  end

  after { Kimera::RUNTIME.reset! }

  it "records every covering test that fails, errs or times out alone with the mutant on", :aggregate_failures do
    runs = []
    result = shift(adapter(runs)).evaluate(target)
    expect([result.status, result.failing_tests]).to(eq([:killed, ["t1"]]))
    expect(result.killing_tests).to(eq(%w[t1 t2 raise hang]))
    expect(runs.drop(1)).to(eq([[target, ["t2"]], [target, ["t3"]], [target, ["raise"]], [target, ["hang"]]]))
    expect(result.message[:kills]).to(eq(%w[t1 t2 raise hang]))
  end

  it "counts a test whose process dies with the mutant on as a killer" do
    dying = Class.new(InlineZygote) do
      define_method(:call) { |&block| Kimera::RUNTIME.active && @armed ? raise(Kimera::Execution::Zygote::Died, "gone") : super(&block) }
      define_method(:arm!) { @armed = true }
    end.new
    census = described_class.new(probe: nil, isolation: Kimera::Execution::Isolation.new, zygote: dying.tap(&:arm!))
    expect(census.killers(target, %w[t9], [])).to(eq(%w[t9]))
  end

  it "records no killers without test quality, nor for a mutant that survives", :aggregate_failures do
    expect(shift(adapter, quality: false).evaluate(target).killing_tests).to(be_nil)
    survivor = Kimera::Execution::Shift.new(
      adapter: adapter, registry: registry, coverage: { target => %w[t3] }, soft_timeout: 0.2,
      zygote: InlineZygote.new, quality: true
    )
    expect(survivor.evaluate(target).then { |r| [r.status, r.killing_tests] }).to(eq([:survived, nil]))
  end
end
