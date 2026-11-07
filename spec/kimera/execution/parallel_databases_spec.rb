# frozen_string_literal: true

require "kimera/execution/baseline_failure"
require "kimera/execution/boot"
require "kimera/execution/baseline_failure/mirror"
require "kimera/execution/isolated_child_command"
require "kimera/execution/memory_databases"
require "kimera/execution/mirror_database"
require "kimera/execution/numbered_databases"
require "kimera/execution/parallel_databases"
require "kimera/execution/parent_connections"
require "kimera/execution/worker_databases"
require "stringio"
require "tmpdir"

using PointFields

RSpec.describe(Kimera::Execution::ParallelDatabases, :aggregate_failures) do
  # A warm worker (kimera's own, running this suite) carries its own
  # TEST_ENV_NUMBER; each example starts without one and leaves it as found.
  around do |example|
    inherited = ENV.delete("TEST_ENV_NUMBER")
    example.run
    inherited ? ENV.store("TEST_ENV_NUMBER", inherited) : ENV.delete("TEST_ENV_NUMBER")
  end

  def config(adapter, database) = FakeRails::Config.new(adapter, database)

  # A test database whose schema dump is there to load, and the Active Record
  # on it, whose connection pools are +pools+.
  def record(database, adapter: "sqlite3", pools: [])
    stub_const("ActiveRecord::Tasks::DatabaseTasks", FakeRails::Tasks.new(__FILE__))
    stub_const("ActiveRecord::ConnectionHandling::DEFAULT_ENV", -> { "test" })
    handler = FakeRails::Pools.new(pools)
    stub_const("ActiveRecord::Base", FakeRails::Base.new(config(adapter, database), handler: handler))
  end

  # Stand-in for ActiveRecord::DatabaseConfigurations: +names+ maps the
  # worker's TEST_ENV_NUMBER to its test database names.
  def configurations_for(names, env)
    Class.new do
      define_method(:initialize) do |*|
        @named =
          names.call(env.fetch("TEST_ENV_NUMBER", nil)).map do |db|
            FakeRails::Config.new("postgresql", db, "primary")
          end
      end
      define_method(:configs_for) do |env_name:, name: nil|
        named = env_name == "test" ? @named : []
        name ? named.first : named
      end
    end
  end

  # A Rails whose database.yml names the test database as +names+ does, the
  # Active Record on it, and the tasks that rebuild a database from its schema.
  def rails(names, env = ENV)
    configurations = configurations_for(names, env)
    stub_const("ActiveRecord::DatabaseConfigurations", configurations)
    stub_const("ActiveRecord::ConnectionHandling::DEFAULT_ENV", -> { "test" })
    stub_const("ActiveRecord::Tasks::DatabaseTasks", FakeRails::Tasks.new(__FILE__))
    base = FakeRails::Base.new(config("postgresql", "app_test"), configurations: configurations.new)
    stub_const("ActiveRecord::Base", base)
    stub_const("Rails", FakeRails::Application.new({}))
  end

  def parallelization(after: [], before: [])
    par = Module.new
    par.define_singleton_method(:after_fork_hooks) { Array(after) }
    par.define_singleton_method(:before_fork_hooks) { Array(before) }
    stub_const("ActiveSupport::Testing::Parallelization", par)
  end

  describe Kimera::Execution::MemoryDatabases do
    it "knows SQLite's in-memory names, and only SQLite's" do
      memory = [":memory:", "file::memory:?cache=shared", "file:db?mode=memory&cache=shared"]
      expect(memory.map { |name| described_class::NAMED.call(config("sqlite3", name)) }).to(all(be(true)))
      expect(described_class::NAMED.call(config("sqlite3", "db/test.sqlite3"))).to(be(false))
      expect(described_class::NAMED.call(config("postgresql", ":memory:"))).to(be(false))
    end

    it "reads the current connection's database, false without Active Record" do
      expect(described_class.new.current?).to(be(false))
      record(":memory:")
      expect(described_class.new.current?).to(be(true))
      record("db/test.sqlite3")
      expect(described_class.new.current?).to(be(false))
    end

    def handle(filename, closed: false, alive: true) = FakeRails::Handle.new(filename, closed, alive)

    it "holds an open, live in-memory handle only" do
      expect(described_class::HELD.call(handle(""))).to(be(true))
      expect(described_class::HELD.call(handle("/db/test.sqlite3"))).to(be(false))
      expect(described_class::HELD.call(handle("", closed: true))).to(be(false))
      expect(described_class::HELD.call(handle("", alive: false))).to(be(false))
      expect(described_class::HELD.call(Object.new)).to(be(false))
    end

    # R3K7: sqlite3 >= 2 closes every writable handle a fork inherits, and
    # the in-memory schema the suite loaded went with it.
    def forked(handles)
      closed = []
      safety = Module.new
      safety.instance_variable_set(:@databases, handles)
      safety.define_singleton_method(:discard) do
        handles = instance_variable_get(:@databases)
        handles.each { |db| closed << db.filename }
        handles.clear
      end
      stub_const("SQLite3::ForkSafety", safety)
      Kimera::Execution::Boot.new(adapter: nil, isolate: false).__send__(:keep!)
      safety.discard
      [closed, safety.instance_variable_get(:@databases).map(&:filename)]
    end

    it "lets a fork keep its in-memory handles, closing the rest as sqlite3 does" do
      closed, kept = forked([handle(""), handle("/db/test.sqlite3")])
      expect(closed).to(eq(["/db/test.sqlite3"]))
      expect(kept).to(eq([""]))
    end

    # A connection pool that discards itself as Active Record's does after a fork.
    def pool_class
      pool =
        Class.new do
          attr_reader :db_config, :discarded

          def initialize(db_config) = @db_config = db_config
          def discard! = @discarded = true
          def discard_pool! = discard!
        end
      pool.prepend(described_class::INHERITED)
    end

    it "keeps an in-memory pool when Active Record discards pools after a fork" do
      pools = [":memory:", "db/t.sqlite3"].map { |name| pool_class.new(config("sqlite3", name)) }
      expect(pools.each(&:discard_pool!).map(&:discarded)).to(eq([nil, true]))
    end
  end

  describe "numbering" do
    it "numbers processes as parallel_tests does" do
      expect(
        [0, 1, 2].map do |index|
          described_class.new.numbered(index).fetch("TEST_ENV_NUMBER")
        end
      ).to(eq(["", "2", "3"]))
      expect(described_class.new.numbered(1)).to(eq("TEST_ENV_NUMBER" => "2"))
    end

    # K3-4: Rails before 8.1 has no switch, and always parallelized databases.
    it "is on before Rails 8.1" do
      stub_const("ActiveSupport", Module.new)
      expect(described_class.new.enabled?).to(be(true))
    end

    def enabled_by?(flag)
      ActiveSupport.define_singleton_method(:parallelize_test_databases) { flag }
      described_class.new.enabled?
    end

    it "follows the switch after" do
      stub_const("ActiveSupport", Module.new)
      expect([true, false].map { |flag| enabled_by?(flag) }).to(eq([true, false]))
    end
  end

  # thredded's dummy app migrates at load and has no schema file; Rails'
  # after-fork hook aborted every worker trying to load one.
  describe "a schema file to load each worker's database from" do
    def schema_at(path, failure: nil)
      stub_const("ActiveRecord::ConnectionHandling::DEFAULT_ENV", -> { "test" })
      stub_const("ActiveRecord::Tasks::DatabaseTasks", FakeRails::Tasks.new(path, failure: failure))
    end

    # An Active Record whose test configurations are +configs+.
    def primary(configs = [config("postgresql", "app_test")])
      FakeRails::Base.new(configs.first, configurations: FakeRails::Configurations.new(configs))
    end

    def configured(present)
      Dir.mktmpdir do |dir|
        schema = File.join(dir, "schema.rb")
        File.write(schema, "") if present
        schema_at(schema)
        return described_class.new(record: primary).loadable?
      end
    end

    it "reads the suite's own Active Record by default" do
      Dir.mktmpdir do |dir|
        stub_const("ActiveRecord::Base", primary)
        schema_at(File.join(dir, "missing.rb"))
        expect(described_class.new.loadable?).to(be(false))
      end
    end

    it "is there only when every test database has its schema dump" do
      expect(configured(true)).to(be(true))
      expect(configured(false)).to(be(false))
      expect(described_class.new(record: nil).loadable?).to(be(true))
    end

    # R5-KL3: cancancan connects to `:memory:` in a `before`, with no configuration to load.
    it "is not there when the suite configures no test database" do
      schema_at(__FILE__)
      expect(described_class.new(record: primary([])).loadable?).to(be(false))
    end

    # R4-KR1 (K3-5): a plain Active Record suite has no Rails for db_dir.
    it "is not there when Active Record cannot work out the schema path" do
      schema_at("db/schema.rb", failure: NameError.new("primary::Rails"))
      expect(described_class.new(record: primary).loadable?).to(be(false))
    end
  end

  describe Kimera::Execution::WorkerDatabases do
    subject(:databases) { described_class.new(jobs: 2, errors: errors, copies: FakeCopies.new(possible: false)) }

    let(:errors) { StringIO.new }

    def switch(flag)
      stub_const("ActiveSupport", Module.new) unless defined?(ActiveSupport)
      ActiveSupport.define_singleton_method(:parallelize_test_databases) { flag }
    end

    # Rails 8.0's Parallelization has after-fork hooks only.
    def after_hooks_only
      par = Module.new
      par.define_singleton_method(:after_fork_hooks) { [->(_i) {}] }
      stub_const("ActiveSupport::Testing::Parallelization", par)
    end

    it "forks on a Rails with no before-fork hooks" do
      after_hooks_only
      record("db/test.sqlite3")
      expect { databases.before_fork }.not_to(raise_error)
    end

    # Workers on one MySQL database, with no schema file to load each their own from.
    def schemaless
      parallelization(after: ->(_i) {})
      record("app_test", adapter: "mysql2")
      stub_const("ActiveRecord::Tasks::DatabaseTasks", FakeRails::Tasks.new("/no/such/schema.rb"))
    end

    it "stays off, and says the workers share one database, without a schema file to load from" do
      schemaless
      expect(databases.active?).to(be(false))
      databases.before_fork
      expect(errors.string).to(include("share one test database (app_test)"))
    end

    it "turns on before Rails 8.1 once the hook is registered" do
      parallelization(after: ->(_i) {})
      expect(databases.active?).to(be(true))
    end

    # R3K6: renaming ":memory:" made files named ":memory:_0" in the project.
    def renamed(database)
      calls = []
      record(database)
      parallelization(after: ->(index) { calls << index })
      databases.after_fork(1)
      calls
    end

    it "never renames an in-memory database, and still renames a file" do
      expect(renamed(":memory:")).to(be_empty)
      expect(renamed("db/test.sqlite3")).to(eq([1]))
    end

    it "numbers each parallel worker, as parallel_tests does" do
      parallelization
      databases.after_fork(2)
      expect(ENV.fetch("TEST_ENV_NUMBER")).to(eq("3"))
      described_class.new(jobs: 1).after_fork(0)
      expect(ENV.fetch("TEST_ENV_NUMBER")).to(eq("3"))
    end

    def shared(database = "app_test", adapter: "mysql2")
      record(database, adapter: adapter)
      2.times { databases.before_fork }
      errors.string
    end

    it "says once when workers would share one database" do
      expect(shared.scan("share one test database (app_test)").size).to(eq(1))
    end

    it "says nothing of an in-memory database: each fork has its own copy" do
      expect(shared(":memory:", adapter: "sqlite3")).to(be_empty)
    end

    # K3-5: the parent's own connections block a fork's database.
    it "closes the parent's connections before the workers fork" do
      connections = FakeConnections.new
      databases.before_fork(connections)
      expect(connections.released).to(eq(1))
    end

    it "says nothing of one worker, which has the database to itself" do
      record("app_test", adapter: "postgresql")
      described_class.new(jobs: 1, errors: errors).before_fork
      expect(errors.string).to(be_empty)
    end

    # The databases a PostgreSQL suite with numbered databases rebuilt, after two before-fork calls.
    def prepared
      switch(false)
      rails(->(number) { ["app_test#{number}"] })
      2.times { databases.before_fork }
      ActiveRecord::Tasks::DatabaseTasks.rebuilt.map(&:database)
    end

    it "creates and loads each numbered database once, before the workers fork" do
      expect(prepared).to(eq(["app_test2"]))
      expect(errors.string).to(be_empty)
    end

    it "moves a worker onto its numbered database when no Rails hook does" do
      parallelization
      rails(->(number) { ["app_test#{number}"] })
      databases.after_fork(1)
      expect(ActiveRecord::Base.established).to(eq([nil]))
    end
  end

  # K3-5: the parent's own idle session blocked a mirror's drop_current.
  describe Kimera::Execution::ParentConnections do
    def pools(handler)
      stub_const("ActiveRecord::Base", FakeRails::Base.new(config("pg", "t"), handler: handler))
    end

    it "disconnects every pool the parent opened" do
      pool = FakeRails::Pool.new
      pools(FakeRails::Pools.new([pool]))
      described_class.new.release!
      expect(pool).to(be_disconnected)
    end

    it "reads the pools of Rails before 7.1 too" do
      pool = FakeRails::Pool.new
      pools(FakeRails::ListedPools.new([pool]))
      described_class.new.release!
      expect(pool).to(be_disconnected)
    end

    it "keeps an in-memory database's connection, which holds its schema" do
      pool = FakeRails::Pool.new
      record(":memory:", pools: [pool])
      described_class.new.release!
      expect(pool).not_to(be_disconnected)
    end

    it "does nothing without Active Record, and lets go of every pool but one that will not", :aggregate_failures do
      expect(described_class.new.release!).to(eq([]))
      FakeRails.errors(self)
      pool = FakeRails::Pool.new
      pools(FakeRails::Pools.new([FakeRails::BusyPool.new, pool]))
      expect([described_class.new.release!, pool.disconnected?]).to(eq([[pool], true]))
    end
  end

  describe Kimera::Execution::NumberedDatabases do
    subject(:numbered) { described_class.new(tolerance: Kimera::Execution::Tolerance.new(errors)) }

    let(:errors) { StringIO.new }

    it "is numbered when database.yml names the database by TEST_ENV_NUMBER" do
      rails(->(number) { ["app_test#{number}"] })
      expect(numbered.numbered?).to(be(true))
      rails(->(_number) { ["app_test"] })
      expect(numbered.numbered?).to(be(false))
    end

    it "is not numbered without Rails" do
      expect(numbered.numbered?).to(be(false))
    end

    it "creates and loads a worker's renamed database" do
      rails(->(number) { ["app_test#{number}"] })
      numbered.prepare(2)
      expect(ActiveRecord::Tasks::DatabaseTasks.rebuilt.map(&:database)).to(eq(["app_test3"]))
    end

    it "says which worker's database it could not create" do
      rails(->(number) { ["app_test#{number}"] })
      stub_const("ActiveRecord::Tasks::DatabaseTasks", FakeRails::Tasks.new(failure: RuntimeError.new("denied")))
      numbered.prepare(1)
      expect(errors.string).to(eq("kimera: could not create the database for worker 1 (RuntimeError: denied)\n"))
    end

    it "reconnects a worker to its own database, leaving TEST_ENV_NUMBER as it found it" do
      rails(->(number) { ["app_test#{number}"] })
      numbered.adopt(1)
      expect(ActiveRecord::Base.established).to(eq([nil]))
      expect(ENV.key?("TEST_ENV_NUMBER")).to(be(false))
      expect(ActiveRecord::Base.configurations.configs_for(env_name: "test").map(&:database)).to(eq(["app_test2"]))
    end

    # The suite's own environment, once a worker adopted its database through it.
    def adopted(env)
      rails(->(number) { ["app_test#{number}"] }, env)
      described_class.new(tolerance: Kimera::Execution::Tolerance.new(errors), env: env).adopt(1)
      env
    end

    it "restores a TEST_ENV_NUMBER it found set in the suite's own environment", :aggregate_failures do
      expect(adopted({ "TEST_ENV_NUMBER" => "7" })).to(eq("TEST_ENV_NUMBER" => "7"))
      expect(ActiveRecord::Base.established).to(eq([nil]))
    end

    it "leaves no TEST_ENV_NUMBER in a suite environment that had none", :aggregate_failures do
      expect(adopted({})).to(eq({}))
      expect(ActiveRecord::Base.established).to(eq([nil]))
    end

    it "is not numbered outside the test environment" do
      rails(->(number) { ["app_test#{number}"] })
      stub_const("ActiveRecord::ConnectionHandling::DEFAULT_ENV", -> { "development" })
      expect(numbered.numbered?).to(be(false))
    end

    it "stays on the parent's database when the name does not change" do
      rails(->(_number) { ["app_test"] })
      numbered.adopt(1)
      expect(ActiveRecord::Base.established).to(eq([]))
    end
  end

  describe Kimera::Execution::MirrorDatabase do
    # The slots the Rails hook renamed mirror 3's database for, as it adopts each database in turn.
    def renames(databases)
      calls = []
      parallelization(after: ->(slot) { calls << slot })
      mirror = described_class.new(3, copies: FakeCopies.new)
      fake_feature("active_record/test_databases")
      databases.each do |database|
        record(database)
        mirror.adopt
      end
      calls
    end

    it "renames a mirror's database before Rails 8.1, never an in-memory one" do
      expect(renames(["db/test.sqlite3", ":memory:"])).to(eq([3]))
    end
  end

  # The environment an isolated child for the mirror slot starts with.
  def mirror_environment(slot)
    Dir.mktmpdir do |dir|
      child = Kimera::Execution::IsolatedPlan::ChildCommand.new(framework: "rspec", test_files: [], root: dir)
      child.command(dir, child.request([], slot: slot), ledger: File.join(dir, "l"), paths: []).first
    end
  end

  it "hands each concurrent mirror its own TEST_ENV_NUMBER" do
    expect([1, nil].map { |slot| mirror_environment(slot) })
      .to(eq([{ "KIMERA" => "1", "TEST_ENV_NUMBER" => "2" }, { "KIMERA" => "1" }]))
  end

  it "names a database another session holds when a mirror cannot drop it" do
    held = Kimera::Execution::BaselineFailure::Mirror.new("PG::ObjectInUse: database is being accessed", "  hint")
    plain = Kimera::Execution::BaselineFailure::Mirror.new("failing: t1", "  hint")
    expect(held.to_s).to(end_with(Kimera::Execution::BaselineFailure::Mirror::HELD))
    expect(plain.to_s).to(end_with("  hint"))
  end
end
