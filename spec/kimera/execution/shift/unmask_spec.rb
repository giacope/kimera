# frozen_string_literal: true

require "kimera/execution/shift"
require "kimera/frameworks/suite"
require "kimera/registry/builder"

# A survivor's covering tests ran together in one process, where an earlier
# test can load what the mutant broke and hide it. Under confirm_survivors
# each test then runs alone in a fresh process with the mutant on, fastest
# first and at most CAP of them; a failure kills only if the test passes alone
# with the mutant off.
RSpec.describe(Kimera::Execution::Shift::Unmask) do
  let(:registry) do
    Kimera::RegistryScan.new.source("def a(x, y)\n  x > y\nend\n", file: "calc.rb")
  end

  let(:target) { registry.each.first.first.id }

  after { Kimera::RUNTIME.reset! }

  # +script+ maps a test to the outcomes of its successive runs; unscripted
  # runs pass.
  def scripted(script)
    Class.new do
      attr_reader :log

      define_method(:initialize) do
        @script = script.transform_values(&:dup)
        @log = []
      end

      define_method(:run) do |ids|
        id = ids.first
        @log << [id, Kimera::RUNTIME.active]
        passed = @script.fetch(id, []).shift != :fail
        failed = passed ? [] : [id]
        Kimera::Frameworks::RunOutcome.new(passed: passed, failed_ids: failed, failures: failed.to_h { [it, "boom"] })
      end
    end.new
  end

  def judged(adapter, tests, **)
    Kimera::Execution::Shift.new(
      adapter: adapter, registry: registry, coverage: { target => tests }, soft_timeout: nil,
      zygote: InlineZygote.new, confirm: true, **
    ).evaluate(target)
  end

  it "kills a survivor whose test fails alone with the mutant on and passes alone with it off", :aggregate_failures do
    adapter = scripted({ "t2" => %i[pass fail pass] })
    result = judged(adapter, %w[t1 t2])
    expect([result.status, result.failing_tests]).to(eq([:killed, ["t2"]]))
    expect(result.detail).to(eq("#{described_class::NOTE}: boom"))
    expect(adapter.log).to(eq([["t1", target], ["t2", target], ["t1", target], ["t2", target], ["t2", nil]]))
  end

  it "keeps the survivor when the test fails alone without the mutant too" do
    expect(judged(scripted({ "t2" => %i[pass fail fail] }), %w[t1 t2]).status).to(eq(:survived))
  end

  it "confirms nothing unless asked", :aggregate_failures do
    adapter = scripted({ "t2" => %i[pass fail] })
    expect(judged(adapter, %w[t1 t2], confirm: false).status).to(eq(:survived))
    expect(adapter.log.size).to(eq(2))
  end

  it "runs the fastest tests first and at most CAP of them", :aggregate_failures do
    tests = Array.new(described_class::CAP + 1) { "t#{it}" }
    adapter = scripted({})
    judged(adapter, tests, timings: { "t9" => 0.01 })
    alone = adapter.log.drop(tests.size)
    expect(alone.size).to(eq(described_class::CAP))
    expect(alone.first).to(eq(["t9", target]))
  end

  # A timeout found alone carries no failure messages to annotate.
  describe "a test that hangs alone" do
    let(:clock) { [0.0] }

    before { stub_const("Kimera::Execution::Shift::Deadline::CLOCK", -> { clock.first }) }

    # +script+ maps a test to its successive runs, as [seconds, passed?] pairs.
    def timed(script)
      now = clock
      Class.new do
        define_method(:initialize) { @script = script.transform_values(&:dup) }

        define_method(:run) do |ids|
          took, passed = @script.fetch(ids.first, []).shift || [0.0, true]
          now[0] += took
          Kimera::Frameworks::RunOutcome.new(passed: passed, failed_ids: passed ? [] : ids)
        end
      end.new
    end

    it "times out a survivor whose test hangs alone with the mutant on and passes quickly without it" do
      adapter = timed({ "t2" => [[0.1, true], [6.0, true], [0.4, true], [0.4, true]] })
      result = Kimera::Execution::Shift.new(
        adapter: adapter, registry: registry, coverage: { target => %w[t1 t2] }, soft_timeout: 5.0,
        zygote: InlineZygote.new, confirm: true
      ).evaluate(target)
      expect(result.status).to(eq(:timeout))
    end

    # Slow without the mutant too, the hang can't be laid on the mutant.
    it "keeps the survivor when its test hangs alone and runs slow without the mutant too" do
      adapter = timed({ "t2" => [[0.1, true], [6.0, true], [4.0, true]] })
      result = Kimera::Execution::Shift.new(
        adapter: adapter, registry: registry, coverage: { target => %w[t1 t2] }, soft_timeout: 5.0,
        zygote: InlineZygote.new, confirm: true
      ).evaluate(target)
      expect(result.status).to(eq(:survived))
    end
  end
end
