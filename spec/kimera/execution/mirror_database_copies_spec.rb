# frozen_string_literal: true

require "kimera/execution/mirror_database"

RSpec.describe(Kimera::Execution::MirrorDatabase) do
  let(:copies) { FakeCopies.new }

  before do
    stub_const("ActiveRecord::Base", FakeRails::Base.new(FakeRails::Config.new("postgresql", "app_test")))
    stub_const("ActiveRecord::Tasks::DatabaseTasks", FakeRails::Tasks.new("/no/such/schema.rb"))
    stub_const("ActiveRecord::ConnectionHandling::DEFAULT_ENV", -> { "test" })
    stub_const("ActiveSupport::Testing::Parallelization", Module.new)
  end

  it "has the parent copy the database for the mirrors' slots" do
    described_class.new(nil, copies: copies).prepare(1...3)
    expect(copies.prepared).to(eq([1...3]))
  end

  it "copies nothing when Rails loads each mirror's database from the schema" do
    stub_const("ActiveRecord::Tasks::DatabaseTasks", FakeRails::Tasks.new(__FILE__))
    described_class.new(nil, copies: copies).prepare(1...3)
    expect(copies.prepared).to(eq([]))
  end

  it "copies nothing when the adapter cannot copy" do
    uncopied = FakeCopies.new(possible: false)
    described_class.new(nil, copies: uncopied).prepare(1...3)
    expect(uncopied.prepared).to(eq([]))
  end

  it "takes its slot's copy" do
    described_class.new(2, copies: copies).adopt
    expect(copies.adopted).to(eq([2]))
  end

  it "takes no copy as the only mirror" do
    described_class.new(nil, copies: copies).adopt
    expect(copies.adopted).to(eq([]))
  end
end
