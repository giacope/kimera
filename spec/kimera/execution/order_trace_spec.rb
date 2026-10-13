# frozen_string_literal: true

require "kimera/execution/order_trace"
require "kimera/registry/builder"

# A mutant the in-order run of the suite reaches but no single test does in a
# fresh process is sent to the isolated tier with the reason.
RSpec.describe(Kimera::Execution::OrderTrace) do
  let(:registry) do
    Kimera::RegistryScan.new.source("def a(x, y)\n  x > y\nend\n\ndef b(x, y)\n  x < y\nend\n", file: "calc.rb")
  end

  let(:ids) { registry.each.map { |mutant, point| [mutant.id, point] }.uniq(&:last).map(&:first) }

  def reasons = registry.points.map(&:revisit)

  def ran(touched) = Struct.new(:sequence).new({ "touched" => touched })

  it "marks a point the ordered run reached that no test covers" do
    first, last = ids
    described_class.new(registry).mark!(ran([first, last]), { first => ["t1"], last.to_s => [] })
    expect(reasons).to(eq([nil, Kimera::MutationPoint::ORDER_REASON]))
  end

  it "leaves a point the ordered run did not reach, or a test covers" do
    first, last = ids
    described_class.new(registry).mark!(ran([first, 999]), { first.to_s => ["t1"], last => [] })
    expect(reasons).to(eq([nil, nil]))
  end

  it "leaves a point that only the isolated tier judges" do
    registry.points.last.unsafe!("class body")
    described_class.new(registry).mark!(ran([ids.last]), {})
    expect(reasons.last).to(be_nil)
  end

  it "marks nothing when the run in order dies" do
    dead = Object.new.tap { |run| run.define_singleton_method(:sequence) { raise(Kimera::Execution::Zygote::Died, "") } }
    described_class.new(registry).mark!(dead, {})
    expect(reasons).to(eq([nil, nil]))
  end
end
