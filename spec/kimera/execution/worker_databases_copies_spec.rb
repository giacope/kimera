# frozen_string_literal: true

require "kimera/execution/worker_databases"
require "stringio"

RSpec.describe(Kimera::Execution::WorkerDatabases) do
  let(:errors) { StringIO.new }
  let(:copies) { FakeCopies.new }

  def databases(jobs: 3, copies: self.copies)
    stub_const("ActiveRecord::Base", FakeRails::Base.new(FakeRails::Config.new("postgresql", "app_test")))
    described_class.new(jobs: jobs, errors: errors, env: {}, copies: copies)
  end

  it "copies the parent's database, once, for the workers past the first, and says nothing", :aggregate_failures do
    built = databases
    2.times { built.before_fork(FakeConnections.new) }
    expect(copies.prepared).to(eq([1...3]))
    expect(errors.string).to(eq(""))
  end

  it "says the workers share one database when the adapter cannot copy" do
    databases(copies: FakeCopies.new(possible: false)).before_fork(FakeConnections.new)
    expect(errors.string).to(include("the 3 workers share one test database (app_test)"))
  end

  it "leaves a lone worker on the parent's database" do
    databases(jobs: 1).before_fork(FakeConnections.new)
    expect(copies.prepared).to(eq([]))
  end

  it "has each worker take its copy" do
    databases.after_fork(2)
    expect(copies.adopted).to(eq([2]))
  end
end
