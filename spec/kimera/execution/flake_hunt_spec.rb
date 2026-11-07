# frozen_string_literal: true

require "kimera/execution/flake_hunt"
require "kimera/execution/flake_runs"
require "kimera/execution/null_progress"
require "kimera/execution/test_filter"
require "kimera/frameworks/suite"
require "kimera/registry/builder"

RSpec.describe(Kimera::Execution::FlakeHunt, :aggregate_failures) do
  let(:adapter) do
    Class.new(Kimera::Frameworks::Suite) do
      def test_ids = %w[t1 t2 t3 t4]
    end.new
  end
  let(:registry) { Kimera::RegistryScan.new.source("def a(x)\n  x > 1\nend\n", file: "a.rb") }
  let(:filter) { Kimera::Execution::TestFilter.new(registry: registry) }
  let(:progress) { Kimera::Execution::NullProgress.new }
  let(:env) { { "KIMERA_SEED" => "11" } }

  def drive(log, tests, spawner, listeners)
    seed = Integer(env.fetch("KIMERA_SEED"), 10)
    log << [seed, tests, spawner.call]
    failing = { 12 => %w[t2], 13 => %w[t2 t1] }.fetch(seed, [])
    tests.each { |test| listeners.resolved("id" => test, "passed" => !failing.include?(test)) }
    listeners.lost("t3", :timeout, []) if seed == 13
  end

  def driver(log)
    drive = method(:drive).curry[log]
    Class.new do
      define_method(:spawner) { |entry| -> { entry } }
      define_method(:drive) { |tests, spawner, listeners| drive.call(tests, spawner, listeners) }
    end.new
  end

  def runs(seed: nil, flaky_runs: nil, filter: nil) = Kimera::Execution::FlakeRuns.new(seed, flaky_runs, filter)

  def hunt(log, **settings)
    described_class.new(adapter, driver(log), progress, env: env).call(
      { 1 => %w[t2 t1], 2 => %w[t3], 3 => %w[t4] }, [1, 2], runs(**settings)
    )
  end

  it "reruns the tests that cover the mutants in scope, once per seed after the run's own, in suite order" do
    log = []
    hunt(log, seed: 11, flaky_runs: 2, filter: filter)
    expect(log).to(eq([[12, %w[t1 t2 t3], :coverage], [13, %w[t1 t2 t3], :coverage]]))
    expect(env).to(eq("KIMERA_SEED" => "11"))
  end

  it "returns what it found, and flags each test a rerun failed or lost, so it kills nothing" do
    record = hunt([], seed: 11, flaky_runs: 2, filter: filter)
    expect(record.flaky).to(eq(%w[t2 t1 t3]))
    expect(filter.keep("a.rb", %w[t1 t2 t3 t4])).to(eq(%w[t4]))
    expect(record.to_h.values_at("runs", "seeds", "tests")).to(eq([2, [12, 13], 3]))
  end

  it "covers every mutant when no scope is given" do
    log = []
    described_class.new(adapter, driver(log), progress, env: env)
      .call({ 3 => %w[t2] }, nil, runs(seed: 1, flaky_runs: 1))
    expect(log).to(eq([[2, %w[t2], :coverage]]))
  end

  it "draws fresh seeds without a run seed, and leaves the environment unseeded after" do
    env.delete("KIMERA_SEED")
    log = []
    hunt(log, seed: nil, flaky_runs: 3, filter: filter)
    seeds = log.map(&:first)
    expect([seeds.uniq.size, seeds.all? { |seed| seed.between?(0, (2**31) - 1) }, env.key?("KIMERA_SEED")])
      .to(eq([3, true, false]))
  end

  it "does nothing without reruns" do
    log = []
    expect([hunt(log, seed: 11, flaky_runs: 0, filter: filter), hunt(log, filter: filter), log]).to(eq([nil, nil, []]))
    expect(screens?(filter)).to(be(false))
  end

  it "wraps the seed past the top of the range" do
    log = []
    hunt(log, seed: (2**31) - 1, flaky_runs: 2, filter: filter)
    expect(log.map(&:first)).to(eq([0, 1]))
  end

  it "seeds the workers through the environment its pool forks with by default" do
    hunt = described_class.new(adapter, nil, progress)
    expect(hunt.instance_variable_get(:@env)).to(equal(ENV))
  end

  it "labels each rerun's progress with its round and seed, and ticks each test, lost ones too" do
    journal = ProgressJournal.new
    described_class.new(adapter, driver([]), journal, env: env)
      .call({ 1 => %w[t1] }, nil, runs(seed: 12, flaky_runs: 1))
    expect(journal.events).to(eq([[:start, 1, "flaky check 1/1 (seed 13)"], [:tick, nil], [:tick, nil], [:finish]]))
  end
end
