# frozen_string_literal: true

require "kimera/execution/database_copies"
require "stringio"

# Active Record is not in this bundle: a stand-in Base records what a copy
# asks of it, and a fake engine stands in for the server or the file.
RSpec.describe(Kimera::Execution::DatabaseCopies) do
  subject(:copies) { copying(engine) }

  let(:errors) { StringIO.new }
  let(:config) { FakeRails::Config.new("postgresql", "app_test") }
  let(:engine) { FakeEngine.new }
  let(:exits) { [] }
  let(:base) { FakeRails::Base.new(config) }

  before { stub_const("ActiveRecord::Base", base) }

  # Copies made with +engine+ for PostgreSQL, whose exit hooks the spec holds.
  def copying(engine)
    sink = exits
    hooks = Module.new { define_singleton_method(:at_exit) { |&block| sink << block } }
    described_class.new(errors: errors, hooks: hooks, engines: { /postg/i => engine })
  end

  def possible?(adapter, database)
    config.adapter = adapter
    config.database = database
    described_class.new.possible?
  end

  it "copies the database for each process it is given, as <database>_<n>" do
    copies.prepare(1...3)
    expect([engine.config, engine.copied]).to(eq([config, %w[app_test_1 app_test_2]]))
  end

  it "drops the copies it made when the run ends" do
    copies.prepare([1])
    exits.each(&:call)
    expect(engine.removed).to(eq(["app_test_1"]))
  end

  # Runs the exit hooks in a fork, which exits 0 when they removed nothing.
  def exited_fork
    forked =
      fork do
        exits.each(&:call)
      ensure
        exit!(engine.removed.empty? ? 0 : 1)
      end
    Process.wait2(forked).last.exitstatus
  end

  it "leaves the copies to the process that made them, not to a fork that exits" do
    copies.prepare([1])
    expect([exited_fork, engine.removed]).to(eq([0, []]))
  end

  it "says when it cannot copy, and drops no copy it did not make", :aggregate_failures do
    refusing = FakeEngine.new(failing: { [:copy, "app_test_1"] => RuntimeError.new("in use") })
    copying(refusing).prepare([1, 2])
    exits.each(&:call)
    expect(errors.string).to(
      eq(
        "kimera: could not copy the test database app_test for process 1 (RuntimeError: in use); " \
          "it uses the parent's\n"
      )
    )
    expect(refusing.removed).to(eq(["app_test_2"]))
  end

  it "says when it cannot drop a copy" do
    copying(FakeEngine.new(failing: { [:remove, "app_test_1"] => RuntimeError.new("gone") })).prepare([1])
    exits.each(&:call)
    expect(errors.string)
      .to(include("could not drop the copy of the test database app_test for process 1 (RuntimeError: gone)"))
  end

  it "takes the process's copy when there is one" do
    copies.adopt(2)
    expect([config.database, base.established.map(&:database)]).to(eq(["app_test_2", ["app_test_2"]]))
  end

  it "keeps the parent's database when there is no copy" do
    copying(FakeEngine.new(missing: ["app_test_1"])).adopt(1)
    expect([config.database, base.established]).to(eq(["app_test", []]))
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
