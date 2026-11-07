# frozen_string_literal: true

require "kimera/execution/worker_databases"
require "stringio"

RSpec.describe(Kimera::Execution::WorkerDatabases) do
  subject(:databases) { described_class.new(jobs: 3, errors: errors, env: {}, copies: copies) }

  let(:errors) { StringIO.new }
  let(:copies) { FakeCopies.new }

  before do
    stub_const("ActiveRecord::Base", FakeRails::Base.new(FakeRails::Config.new("postgresql", "app_test")))
  end

  it "copies the parent's database, once, for the workers past the first, and says nothing", :aggregate_failures do
    2.times { databases.before_fork(FakeConnections.new) }
    expect(copies.prepared).to(eq([1...3]))
    expect(errors.string).to(eq(""))
  end

  it "says the workers share one database when the adapter cannot copy" do
    described_class.new(jobs: 3, errors: errors, env: {}, copies: FakeCopies.new(possible: false))
      .before_fork(FakeConnections.new)
    expect(errors.string).to(include("the 3 workers share one test database (app_test)"))
  end

  it "leaves a lone worker on the parent's database" do
    described_class.new(jobs: 1, errors: errors, env: {}, copies: copies).before_fork(FakeConnections.new)
    expect(copies.prepared).to(eq([]))
  end

  it "has each worker take its copy" do
    databases.after_fork(2)
    expect(copies.adopted).to(eq([2]))
  end
end
