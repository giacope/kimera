# frozen_string_literal: true

require "kimera/execution/database_copies"
require "stringio"

# Active Record is not in this bundle: a stand-in Base records what a copy
# asks of it, and an engine double stands in for the server or the file.
RSpec.describe(Kimera::Execution::DatabaseCopies) do
  subject(:copies) { described_class.new(errors: errors, hooks: hooks) }

  let(:errors) { StringIO.new }
  let(:config) do
    Struct.new(:adapter, :database) { alias_method(:_database=, :database=) }.new("postgresql", "app_test")
  end
  let(:engine) { instance_double(described_class::Postgres, copy: nil, remove: nil, exist?: true) }
  let(:seen) { { exits: [], established: [] } }

  before do
    current = config
    sink = seen[:established]
    base = Class.new { define_singleton_method(:establish_connection) { |config| sink << config.database } }
    base.define_singleton_method(:connection_db_config) { current }
    stub_const("ActiveRecord::Base", base)
    allow(described_class::Postgres).to(receive(:new).with(config).and_return(engine))
  end

  def hooks
    sink = seen[:exits]
    Module.new { define_singleton_method(:at_exit) { |&block| sink << block } }
  end

  def exits = seen[:exits]

  def established = seen[:established]

  def possible?(adapter, database)
    config.adapter = adapter
    config.database = database
    described_class.new.possible?
  end

  it "copies the database for each process it is given, as <database>_<n>" do
    copies.prepare(1...3)
    %w[app_test_1 app_test_2].each { |name| expect(engine).to(have_received(:copy).with(name)) }
  end

  it "drops the copies it made when the run ends" do
    copies.prepare([1])
    exits.each(&:call)
    expect(engine).to(have_received(:remove).with("app_test_1"))
  end

  it "leaves the copies to the process that made them, not to a fork that exits" do
    allow(Process).to(receive(:pid).and_return(10, 11))
    copies.prepare([1])
    exits.each(&:call)
    expect(engine).not_to(have_received(:remove))
  end

  it "says when it cannot copy, and drops no copy it did not make", :aggregate_failures do
    allow(engine).to(receive(:copy).with("app_test_1").and_raise(RuntimeError, "in use"))
    copies.prepare([1, 2])
    exits.each(&:call)
    expect(errors.string).to(
      eq(
        "kimera: could not copy the test database app_test for process 1 (RuntimeError: in use); " \
          "it uses the parent's\n"
      )
    )
    expect(engine).not_to(have_received(:remove).with("app_test_1"))
  end

  it "says when it cannot drop a copy" do
    allow(engine).to(receive(:remove).and_raise(RuntimeError, "gone"))
    copies.prepare([1])
    exits.each(&:call)
    expect(errors.string)
      .to(include("could not drop the copy of the test database app_test for process 1 (RuntimeError: gone)"))
  end

  it "takes the process's copy when there is one" do
    copies.adopt(2)
    expect([config.database, established]).to(eq(["app_test_2", ["app_test_2"]]))
  end

  it "keeps the parent's database when there is no copy" do
    allow(engine).to(receive(:exist?).with("app_test_1").and_return(false))
    copies.adopt(1)
    expect([config.database, established]).to(eq(["app_test", []]))
  end

  it "copies on PostgreSQL and SQLite, but not on another adapter or an in-memory database" do
    found = [%w[postgresql x], %w[sqlite3 db/x.sqlite3], %w[mysql2 x], %w[sqlite3 :memory:]]
    expect(found.map { |adapter, database| possible?(adapter, database) }).to(eq([true, true, false, false]))
  end

  it "copies nothing without Active Record, or before it has a connection", :aggregate_failures do
    hide_const("ActiveRecord::Base")
    expect([described_class.new.possible?, described_class.new.adopt(1)]).to(eq([false, nil]))
    stub_const("ActiveRecord::Base", Class.new)
    expect(described_class.new.possible?).to(be(false))
  end
end
