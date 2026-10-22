# frozen_string_literal: true

require "kimera/execution/mirror_database"

# A mirror whose database Rails' hook cannot load from a schema file takes the
# copy the parent made of its prepared database.
RSpec.describe(Kimera::Execution::MirrorDatabase) do
  let(:copies) { instance_double(Kimera::Execution::DatabaseCopies, possible?: true, prepare: nil, adopt: nil) }
  let(:parallel) { instance_double(Kimera::Execution::ParallelDatabases, enabled?: true, loadable?: false) }

  before do
    allow(Kimera::Execution::DatabaseCopies).to(receive(:new).and_return(copies))
    allow(Kimera::Execution::ParallelDatabases).to(receive(:new).and_return(parallel))
    stub_const("ActiveRecord::Base", Class.new)
    stub_const("ActiveSupport::Testing::Parallelization", Module.new)
  end

  it "has the parent copy the database for the mirrors' slots" do
    described_class.new(nil).prepare(1...3)
    expect(copies).to(have_received(:prepare).with(1...3))
  end

  it "copies nothing when Rails loads each mirror's database from the schema, or the adapter cannot copy" do
    allow(parallel).to(receive(:loadable?).and_return(true, false))
    allow(copies).to(receive(:possible?).and_return(true, false))
    2.times { described_class.new(nil).prepare(1...3) }
    expect(copies).not_to(have_received(:prepare))
  end

  it "takes its slot's copy" do
    described_class.new(2).adopt
    expect(copies).to(have_received(:adopt).with(2))
  end

  it "takes no copy as the only mirror" do
    described_class.new(nil).adopt
    expect(copies).not_to(have_received(:adopt))
  end
end
