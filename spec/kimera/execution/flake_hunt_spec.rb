# frozen_string_literal: true

require "kimera/execution/flake_hunt"
require "kimera/execution/null_progress"
require "kimera/execution/test_filter"
require "kimera/frameworks/adapter"
require "kimera/registry/builder"

# The driver stands in for the warm pool: it answers each test with the
# result the seed in the environment calls for, as a worker forked then would.
RSpec.describe(Kimera::Execution::FlakeHunt, :aggregate_failures) do
  let(:adapter) do
    Class.new(Kimera::Frameworks::Adapter) do
      def test_ids = %w[t1 t2 t3 t4]
    end.new
  end
  let(:registry) { Kimera::RegistryScan.new.source("def a(x)\n  x > 1\nend\n", file: "a.rb") }
  let(:filter) { Kimera::Execution::TestFilter.new(registry: registry) }
  let(:progress) { Kimera::Execution::NullProgress::NONE }
  let(:env) { { "KIMERA_SEED" => "11" } }

  # Under seed 12, t2 fails; under 13, t2 and t1 fail and t3 times out.
  def drive(log, tests, spawner, listeners)
    seed = Integer(env.fetch("KIMERA_SEED"), 10)
    log << [seed, tests, spawner.call]
    failing = { 12 => %w[t2], 13 => %w[t2 t1] }.fetch(seed, [])
    tests.each { |test| listeners.resolve.call("id" => test, "passed" => !failing.include?(test)) }
    listeners.lost.call("t3", :timeout, nil) if seed == 13
  end

  def driver(log)
    drive = method(:drive).curry[log]
    Class.new do
      define_method(:channel) { :channel }
      define_method(:drive) { |tests, spawner, listeners| drive.call(tests, spawner, listeners) }
    end.new
  end

  def hunt(log, **settings)
    described_class.new(adapter, driver(log), progress, env: env).call(
      { 1 => %w[t2 t1], 2 => %w[t3], 3 => %w[t4] }, [1, 2], settings
    )
  end

  it "reruns the tests that cover the mutants in scope, once per seed after the run's own, in suite order" do
    log = []
    hunt(log, seed: 11, flaky_runs: 2, filter: filter)
    expect(log).to(eq([[12, %w[t1 t2 t3], :channel], [13, %w[t1 t2 t3], :channel]]))
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
    described_class.new(adapter, driver(log), progress, env: env).call({ 3 => %w[t2] }, nil, seed: 1, flaky_runs: 1)
    expect(log).to(eq([[2, %w[t2], :channel]]))
  end

  it "draws fresh seeds without a run seed, and leaves the environment unseeded after" do
    env.delete("KIMERA_SEED")
    log = []
    hunt(log, seed: nil, flaky_runs: 3, filter: filter)
    expect(log.map(&:first)).to(all(be_between(0, (2**31) - 1)))
    expect(log.map(&:first).uniq.size).to(eq(3))
    expect(env).not_to(have_key("KIMERA_SEED"))
  end

  it "does nothing without reruns" do
    log = []
    expect([hunt(log, seed: 11, flaky_runs: 0, filter: filter), hunt(log, filter: filter), log]).to(eq([nil, nil, []]))
    expect(filter.active?).to(be(false))
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
    events = []
    journal = Class.new do
      define_method(:start) { |total, label| events << [:start, total, label] }
      define_method(:tick) { |*| events << :tick }
      define_method(:finish) { events << :finish }
    end.new
    described_class.new(adapter, driver([]), journal, env: env).call({ 1 => %w[t1] }, nil, seed: 12, flaky_runs: 1)
    expect(events).to(eq([[:start, 1, "flaky check 1/1 (seed 13)"], :tick, :tick, :finish]))
  end
end
