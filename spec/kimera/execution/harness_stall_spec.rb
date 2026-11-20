# frozen_string_literal: true

require "kimera/execution/harness"
require "kimera/frameworks/suite"
require "kimera/registry/builder"
require "stringio"

RSpec.describe(Kimera::Execution::Harness) do
  let(:registry) do
    Kimera::RegistryScan.new.source(<<~RUBY, file: "calc.rb")
      def a(x, y)
        x > y
      end
    RUBY
  end

  def suite
    Class.new(Kimera::Frameworks::Suite) do
      def source(_files) = self
      def test_ids = ["A#t"]
    end.new
  end

  def stalling(stalls)
    Class.new do
      define_method(:driver) { self }
      define_method(:spawner) { |entry| entry }
      define_method(:arm) { |**| self }
      define_method(:hunt) { |*| {} }
      define_method(:drive) do |ids, _spawner, listeners, jobs:|
        lost = stalls.shift
        passed = ->(id) { listeners.resolved({ "id" => id, "touched" => [], "passed" => true }) }
        ids.each { |id| lost ? listeners.lost(id, :timeout, lost) : passed.call(id) }
        jobs
      end
    end.new
  end

  def warned(stalls, **)
    errors = StringIO.new
    described_class.build(registry: registry, adapter: suite, errio: errors, rig: stalling(stalls), **).warm!([])
    errors.string
  end

  it "prints the stall notice with the run's hard timeout and width", :aggregate_failures do
    expect(warned([["trace"]], hard_timeout: 7.0, jobs: 3)).to(
      start_with("kimera: 1 baseline test(s) hit the hard timeout (7.0s) with 3 workers")
        .and(end_with("  A#t:\n    trace\n"))
    )
  end

  it "prints nothing when no baseline test stalled" do
    expect(warned([])).to(be_empty)
  end

  it "derives the hard timeout from soft_timeout when not given" do
    expect(warned([["trace"]], soft_timeout: 5.0)).to(include("hard timeout (#{(5.0 * 3) + 1}s)"))
  end

  it "falls back to a 30s hard timeout when soft_timeout is nil" do
    expect(warned([["trace"]], soft_timeout: nil)).to(include("hard timeout (30.0s)"))
  end

  it "clamps jobs to at least 1", :aggregate_failures do
    expect(warned([["trace"]], jobs: 0)).to(include("with 1 workers"))
    expect(warned([["trace"]], jobs: 4)).to(include("with 4 workers"))
  end
end
