# frozen_string_literal: true

require "kimera/execution/mirror_database"

# Each isolated mirror past the first takes a test database of its own, the
# way Rails' parallel test workers do, so concurrent mirrors never share rows.
RSpec.describe(Kimera::Execution::MirrorDatabase, :aggregate_failures) do
  # rails: which of ActiveRecord and Rails' parallel testing are loaded, and
  # whether ActiveSupport answers parallelize_test_databases.
  def test_adopted(slot, parallel: true, rails: %i[record testing], answers: true)
    calls = []
    stub_const("ActiveRecord::Base", Class.new) if rails.include?(:record)
    stub_const("ActiveSupport::Testing::Parallelization", Module.new) if rails.include?(:testing)
    stub_const("ActiveSupport", Module.new) unless defined?(ActiveSupport)
    ActiveSupport.define_singleton_method(:parallelize_test_databases) { parallel } if answers
    if rails.include?(:testing)
      ActiveSupport::Testing::Parallelization.define_singleton_method(:after_fork_hooks) do
        [->(worker) { calls << worker }]
      end
    end
    database = described_class.new(slot)
    allow(database).to(receive(:require))
    [database.adopt, calls, database]
  end

  it "leaves the database alone when there is no schema file to load the mirror's copy from" do
    allow(Kimera::Execution::ParallelDatabases).to(
      receive(:new).and_return(
        instance_double(Kimera::Execution::ParallelDatabases, enabled?: true, loadable?: false)
      )
    )
    expect(test_adopted(2)[1]).to(eq([]))
  end

  it "loads Rails' test databases and runs its after-fork hooks with the mirror's slot" do
    _adopted, calls, database = test_adopted(2)
    expect(calls).to(eq([2]))
    expect(database).to(have_received(:require).with("active_record/test_databases"))
  end

  it "leaves the database alone with one mirror or without parallel test databases" do
    expect(test_adopted(nil)[1]).to(eq([]))
    expect(test_adopted(1, parallel: false)[1]).to(eq([]))
  end

  [[], [:testing], [:record]].each do |loaded|
    it "does nothing outside Rails, or with only part of it loaded (#{loaded.inspect})" do
      _adopted, calls, database = test_adopted(1, rails: loaded)
      expect(calls).to(eq([]))
      expect(database).not_to(have_received(:require))
    end
  end

  # K3-4: before 8.1 Rails had no switch: its hook always renamed the database.
  it "renames the database on a Rails before 8.1, which has no switch" do
    _adopted, calls, database = test_adopted(1, answers: false)
    expect(calls).to(eq([1]))
    expect(database).to(have_received(:require).with("active_record/test_databases"))
  end
end
