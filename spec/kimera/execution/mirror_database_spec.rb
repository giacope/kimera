# frozen_string_literal: true

require "kimera/execution/mirror_database"

# Each isolated mirror past the first takes a test database of its own, the
# way Rails' parallel test workers do, so concurrent mirrors never share rows.
RSpec.describe(Kimera::Execution::MirrorDatabase, :aggregate_failures) do
  def test_adopted(slot, parallel: true)
    calls = []
    stub_const("ActiveRecord::Base", Class.new)
    stub_const("ActiveSupport::Testing::Parallelization", Module.new)
    ActiveSupport.define_singleton_method(:parallelize_test_databases) { parallel }
    ActiveSupport::Testing::Parallelization.define_singleton_method(:after_fork_hooks) do
      [->(worker) { calls << worker }]
    end
    database = described_class.new(slot)
    allow(database).to(receive(:require))
    database.adopt
    calls
  end

  it "runs Rails' after-fork hooks with the mirror's slot, as a parallel test worker would" do
    expect(test_adopted(2)).to(eq([2]))
  end

  it "leaves the database alone with one mirror or without parallel test databases" do
    expect(test_adopted(nil)).to(eq([]))
    expect(test_adopted(1, parallel: false)).to(eq([]))
  end

  it "does nothing outside Rails" do
    expect(described_class.new(1).adopt).to(be_nil)
  end
end
