# frozen_string_literal: true

require "kimera/execution/harness"
require "kimera/registry/registry"

RSpec.describe(Kimera::Execution::Harness) do
  let(:registry) { Kimera::Registry.new }
  let(:events) { [] }

  def harness(isolation:)
    described_class.build(registry: registry, adapter: nil, isolate_db: isolation)
  end

  before do
    # Fake ActiveRecord::Base, so no real database is needed.
    ledger = events
    base =
      Class.new do
        define_singleton_method(:transaction) do |**_opts, &block|
          ledger << :begin
          begin
            block.call
          rescue Kimera::Execution::TransactionIsolation::Rollback
            ledger << :rollback
          end
        end
      end
    stub_const("ActiveRecord::Base", base)
  end

  it "wraps the mutant run in a rolled-back transaction when enabled" do
    h = harness(isolation: true)
    h.isolate!

    h.__send__(:isolation).around { events << :ran }
    expect(events).to(eq(%i[begin ran rollback]))
  end

  it "leaves isolation untouched when disabled" do
    h = harness(isolation: false)
    h.isolate!

    h.__send__(:isolation).around { events << :ran }
    expect(events).to(eq([:ran]))
  end
end
