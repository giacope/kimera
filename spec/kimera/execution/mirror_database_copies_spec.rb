# frozen_string_literal: true

require "kimera/execution/mirror_database"

RSpec.describe(Kimera::Execution::MirrorDatabase) do
  let(:copies) { FakeCopies.new }

  def mirror(slot, store: copies, schema: "/no/such/schema.rb")
    stub_const("ActiveRecord::Base", FakeRails::Base.new(FakeRails::Config.new("postgresql", "app_test")))
    stub_const("ActiveRecord::Tasks::DatabaseTasks", FakeRails::Tasks.new(schema))
    stub_const("ActiveRecord::ConnectionHandling::DEFAULT_ENV", -> { "test" })
    stub_const("ActiveSupport::Testing::Parallelization", Module.new)
    described_class.new(slot, copies: store)
  end

  it "has the parent copy the database for the mirrors' slots" do
    mirror(nil).prepare(1...3)
    expect(copies.prepared).to(eq([1...3]))
  end

  it "copies nothing when Rails loads each mirror's database from the schema" do
    mirror(nil, schema: __FILE__).prepare(1...3)
    expect(copies.prepared).to(eq([]))
  end

  it "copies nothing when the adapter cannot copy" do
    uncopied = FakeCopies.new(possible: false)
    mirror(nil, store: uncopied).prepare(1...3)
    expect(uncopied.prepared).to(eq([]))
  end

  it "takes its slot's copy" do
    mirror(2).adopt
    expect(copies.adopted).to(eq([2]))
  end

  it "takes no copy as the only mirror" do
    mirror(nil).adopt
    expect(copies.adopted).to(eq([]))
  end
end
