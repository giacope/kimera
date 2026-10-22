# frozen_string_literal: true

require "kimera/execution/worker_databases"
require "stringio"

# A suite that migrates its database as it loads leaves no schema file for
# Rails' hook: each warm worker past the first takes a copy the parent made.
RSpec.describe(Kimera::Execution::WorkerDatabases) do
  subject(:databases) { described_class.new(jobs: 3, errors: errors, env: {}) }

  let(:errors) { StringIO.new }
  let(:copies) { instance_double(Kimera::Execution::DatabaseCopies, possible?: true, prepare: nil, adopt: nil) }

  before do
    allow(Kimera::Execution::DatabaseCopies).to(receive(:new).with(errors: errors).and_return(copies))
    parent = instance_double(Kimera::Execution::ParentConnections, release!: nil)
    allow(Kimera::Execution::ParentConnections).to(receive(:new).and_return(parent))
    numbered = instance_double(Kimera::Execution::NumberedDatabases, numbered?: false, adopt: nil)
    allow(Kimera::Execution::NumberedDatabases).to(receive(:new).and_return(numbered))
    stub_const("ActiveRecord::Base", Class.new)
  end

  it "copies the parent's database, once, for the workers past the first, and says nothing", :aggregate_failures do
    2.times { databases.before_fork }
    expect(copies).to(have_received(:prepare).with(1...3).once)
    expect(errors.string).to(eq(""))
  end

  it "says the workers share one database when the adapter cannot copy" do
    allow(copies).to(receive(:possible?).and_return(false))
    allow(ActiveRecord::Base).to(receive(:connection_db_config).and_return(Struct.new(:database).new("app_test")))
    databases.before_fork
    expect(errors.string).to(include("the 3 workers share one test database (app_test)"))
  end

  it "leaves a lone worker on the parent's database" do
    described_class.new(jobs: 1, errors: errors, env: {}).before_fork
    expect(copies).not_to(have_received(:prepare))
  end

  it "has each worker take its copy" do
    databases.after_fork(2)
    expect(copies).to(have_received(:adopt).with(2))
  end
end
