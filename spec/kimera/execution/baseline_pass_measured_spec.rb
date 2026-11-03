# frozen_string_literal: true

require "kimera/execution/baseline_pass"
require "kimera/execution/null_progress"
require "kimera/frameworks/suite"
require "kimera/registry/builder"

# --reuse-coverage measures some of the suite: the tests a stored coverage map
# says can reach the changed code.
RSpec.describe(Kimera::Execution::BaselinePass) do
  let(:registry) { Kimera::RegistryScan.new.source("def a(x) = x > 1\n", file: "calc.rb") }
  let(:adapter) { Class.new(Kimera::Frameworks::Suite) { def test_ids = %w[t1 t2 t3] }.new }
  let(:counted) { [] }

  def meter = ProgressJournal.new(counted)

  def queues(**)
    seen = []
    pass = described_class.new(adapter: adapter, registry: registry, progress: meter, **)
    pass.parallel!(1) do |queue, _jobs, listeners|
      seen << queue
      queue.each { |id| listeners.resolved("t" => "result", "id" => id, "passed" => true, "touched" => []) }
    end
    seen
  end

  it "measures the tests it is told to, asking once, and counts them" do
    asked = []
    expect([queues(measured: ->(ids) { (asked << ids) && ids.last(1) }), asked, counted])
      .to(eq([[%w[t3]], [%w[t1 t2 t3]], [[:start, 1, "baseline"], [:tick, nil], [:finish]]]))
  end

  it "measures every test by default" do
    expect(queues).to(eq([%w[t1 t2 t3]]))
  end
end
