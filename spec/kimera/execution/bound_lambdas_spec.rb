# frozen_string_literal: true

require "fileutils"
require "kimera/execution/schemata"
require "kimera/execution/triage"
require "kimera/registry/builder"
require "tmpdir"

using ResultFields
using PointFields

# R5-KL7: action_policy's LookupChain keeps the lambdas its constants held at
# load; the overlay bound new, guarded ones that the chain never called.
RSpec.describe(Kimera::Execution::BoundLambdas, :aggregate_failures) do
  let(:dir) { Dir.mktmpdir }

  after { FileUtils.remove_entry(dir) }

  def scanned(source)
    path = File.join(dir, "bound_lookup.rb")
    File.write(path, source)
    Kimera::RegistryScan.new(root: dir).build([path])
  end

  def reasons(registry)
    registry.to_a.to_h { |point| [point.location.range.begin, PointVerdict.new(point).unsafe_reason] }
  end

  it "judges a lambda or proc a constant holds in the isolated tier, and leaves other code alone" do
    registry = scanned(<<~RUBY)
      module BoundLookup
        BY_SYMBOL = ->(record) { record.is_a?(Symbol) && record }
        BoundLookup::BY_NAME ||= lambda { |record| record.is_a?(String) && record }
        STEP = proc { |n| n > 1 }
        def self.big?(n) = n > 10
        def self.make = (local = ->(n) { n > 2 })
      end
    RUBY
    described_class.new(registry, dir).hold!("bound_lookup.rb")
    held = Kimera::Reason::BOUND_REASON
    expect(reasons(registry)).to(eq(2 => held, 3 => held, 4 => held, 5 => nil, 6 => nil))
    expect(registry.to_a.find { |point| point.location.range.begin == 2 }.reasons(Kimera::Reason.unreloadable).empty?).to(be(false))
  end

  # action_policy's INFER_FROM_CLASS: `strict_namespace: false => true` was judged by reloading the file, which
  # bound a new lambda the chain never called, so it survived though the plain suite fails with it.
  it "holds the parameter defaults of a constant's lambda too, which would otherwise go to the reload tier" do
    registry = scanned(<<~RUBY)
      module BoundLookup
        INFER = ->(record, strict: false) {
          strict && record
        }
        def self.find(record, strict: false) = strict && record
      end
    RUBY
    before = reasons(registry)
    described_class.new(registry, dir).hold!("bound_lookup.rb")
    expect(before.values_at(2, 3)).to(eq(["constant assignment (computed once)", nil]))
    expect(reasons(registry)).to(eq(2 => held, 3 => held, 5 => nil))
  end

  def held = Kimera::Reason::BOUND_REASON

  # The registry of a chain built at load, after the overlay: the lambda the chain took, and its first mutant.
  def chained
    stub_const("BoundChain", Module.new)
    registry = scanned("module BoundChain\n  STEP = ->(n) { n > 1 }\n  CHAIN = [STEP]\nend\n")
    require(File.join(dir, "bound_lookup.rb"))
    taken = BoundChain::CHAIN.first
    Kimera::Execution::Schemata.new(registry, root: dir).overlay!
    [taken, verdict(registry)]
  end

  def verdict(registry)
    triage = Kimera::Execution::Triage.new(Kimera::Execution::Verdicts.new(registry))
    triage.quarantine(registry.to_a.first.ids.first).status
  end

  it "keeps the constant bound to the lambda the suite took, and calls its mutants isolated_only" do
    taken, status = chained
    expect([BoundChain::STEP, status]).to(eq([taken, :isolated_only]))
  end
end
