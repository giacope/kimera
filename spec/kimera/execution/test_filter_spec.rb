# frozen_string_literal: true

require "kimera/execution/test_filter"
require "kimera/registry/builder"
require "kimera/execution/attribution"

RSpec.describe(Kimera::Execution::TestFilter, :aggregate_failures) do
  let(:registry) do
    Kimera::RegistryScan.new.source("def big?(total)\n  total > 50\nend\n", file: "app/models/order.rb")
  end
  let(:id) { registry.each.first.first.id }
  let(:files) do
    {
      "own" => "spec/models/order_spec.rb", "request" => "spec/requests/orders_spec.rb",
      "also" => "spec/order_spec.rb"
    }
  end
  let(:locate) { ->(test) { files[test] } }
  # The adapter names each test's file as the framework does: relative with ./, or absolute.
  let(:adapter) do
    named = { "own" => "./spec/models/order_spec.rb", "request" => "spec/requests/orders_spec.rb" }
      .merge("abs" => File.expand_path("spec/models/order_spec.rb"), "else" => "/elsewhere/spec/models/order_spec.rb")
    Struct.new(:named) { def test_file(test) = named.fetch(test, "") }.new(named)
  end

  def filter(attribution: Kimera::Execution::Attribution.new, flaky: [])
    described_class.new(registry: registry, attribution: attribution, flaky: flaky, locate: locate)
  end

  it "keeps every test when neither attribution nor flakiness narrows them" do
    plain = described_class.new(registry: registry)
    expect(plain.active?).to(be(false))
    expect(plain.keep("app/models/order.rb", %w[own request])).to(eq(%w[own request]))
    expect(plain.settle(id, %w[request])).to(be_nil)
    expect(plain.screen({ id => %w[request] })).to(eq([{ id => %w[request] }, {}]))
  end

  it "keeps only the unit's own tests, by the file each is declared in" do
    expect(filter.active?).to(be(true))
    expect(filter.keep("app/models/order.rb", %w[own request also])).to(eq(%w[own also]))
  end

  it "builds strict attribution from unit_tests rules, locating each test under the root" do
    ruled = described_class.build(
      registry: registry, adapter: adapter,
      rules: { "app/**/*.rb" => ["spec/requests/{name}s_spec.rb"] }
    )
    expect(ruled.active?).to(be(true))
    expect(ruled.keep("app/models/order.rb", %w[own request abs else ghost])).to(eq(%w[own request abs]))
  end

  it "builds no attribution without rules" do
    plain = described_class.build(registry: registry, adapter: adapter, root: "/elsewhere")
    expect([plain.active?, plain.keep("app/models/order.rb", %w[own else])]).to(eq([false, %w[own else]]))
    rooted = described_class.build(registry: registry, adapter: adapter, root: "/elsewhere", rules: {})
    expect(rooted.keep("app/models/order.rb", %w[own else])).to(eq(%w[else]))
  end

  it "never keeps a flaky test, with or without attribution" do
    expect(filter(flaky: %w[own]).keep("app/models/order.rb", %w[own also])).to(eq(%w[also]))
    unattributed = filter(attribution: Kimera::Execution::Attribution::ANY, flaky: %w[request])
    expect(unattributed.active?).to(be(true))
    expect(unattributed.keep("app/models/order.rb", %w[own request])).to(eq(%w[own]))
  end

  it "settles a mutant only other units' tests reach as uncovered_by_unit, naming its own test files" do
    settled = filter.settle(id, %w[request])
    expect(settled.to_h.slice("mutant_id", "status", "file", "covering_tests"))
      .to(
        eq(
          "mutant_id" => id, "status" => "uncovered_by_unit", "file" => "app/models/order.rb",
          "covering_tests" => %w[request]
        )
      )
    expect(settled.detail).to(
      eq(
        "reached only by other units' tests (attribution: unit); none of its own tests " \
          "(spec/models/order_spec.rb, test/models/order_test.rb, or a unit_tests rule) runs it"
      )
    )
  end

  it "settles a mutant only flaky tests cover as no_coverage, naming them" do
    settled = filter(flaky: %w[own request]).settle(id, %w[own request])
    expect([settled.status, settled.covering_tests]).to(eq([:no_coverage, nil]))
    expect(settled.detail).to(eq("covered only by flaky test(s), which never kill: own, request"))
  end

  it "names only the steady foreign tests of a mutant reached by flaky and foreign ones" do
    settled = filter(flaky: %w[own]).settle(id, %w[own request])
    expect([settled.status, settled.covering_tests]).to(eq([:uncovered_by_unit, %w[request]]))
  end

  it "settles nothing a kept test covers, nor what no test covers" do
    expect(filter.settle(id, %w[request own])).to(be_nil)
    expect(filter.settle(id, [])).to(be_nil)
  end

  it "splits coverage into what each mutant may still be killed by and what is settled" do
    kept, settled = filter.screen({ id => %w[own request], 999 => [] })
    expect(kept).to(eq(id => %w[own], 999 => []))
    expect(settled).to(eq({}))
    kept, settled = filter.screen({ id => %w[request] })
    expect([kept, settled.keys, settled.fetch(id).status]).to(eq([{}, [id], :uncovered_by_unit]))
  end

  it "asks for each test's file once" do
    calls = []
    counting = described_class.new(
      registry: registry, attribution: Kimera::Execution::Attribution.new, locate: ->(test) { (calls << test) && files[test] }
    )
    2.times { counting.keep("app/models/order.rb", %w[own]) }
    expect(calls).to(eq(%w[own]))
  end

  it "treats a test of unknown file as no unit's own" do
    expect(filter.keep("app/models/order.rb", %w[ghost])).to(eq([]))
  end
end
