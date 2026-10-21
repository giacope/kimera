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

RSpec.describe(Kimera::Execution::ParallelDatabases, :aggregate_failures) do
  # A warm worker (kimera's own, running this suite) carries its own
  # TEST_ENV_NUMBER; each example starts without one and leaves it as found.
  around do |example|
    inherited = ENV.delete("TEST_ENV_NUMBER")
    example.run
    inherited ? ENV.store("TEST_ENV_NUMBER", inherited) : ENV.delete("TEST_ENV_NUMBER")
  end

  def config(adapter, database) = Struct.new(:adapter, :database).new(adapter, database)

  def record(database, adapter: "sqlite3")
    base = Class.new
    current = config(adapter, database)
    base.define_singleton_method(:connection_db_config) { current }
    stub_const("ActiveRecord::Base", base)
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

    def handle(filename, closed: false, alive: true)
      double(filename: filename, closed?: closed, weakref_alive?: alive)
    end

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

    it "keeps an in-memory pool when Active Record discards pools after a fork" do
      pool =
        Class.new do
          attr_reader :db_config, :discarded

          def initialize(db_config) = @db_config = db_config
          def discard! = @discarded = true
          def discard_pool! = discard!
        end
      pool.prepend(described_class::INHERITED)
      expect(pool.new(config("sqlite3", ":memory:")).tap(&:discard_pool!).discarded).to(be_nil)
      expect(pool.new(config("sqlite3", "db/t.sqlite3")).tap(&:discard_pool!).discarded).to(be(true))
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
    it "is on before Rails 8.1 and follows the switch after" do
      stub_const("ActiveSupport", Module.new)
      expect(described_class.new.enabled?).to(be(true))
      [true, false].each do |flag|
        ActiveSupport.define_singleton_method(:parallelize_test_databases) { flag }
        expect(described_class.new.enabled?).to(be(flag))
      end
    end
  end

  describe Kimera::Execution::WorkerDatabases do
    subject(:databases) { described_class.new(jobs: 2, errors: errors) }

    let(:errors) { StringIO.new }

    def switch(flag)
      stub_const("ActiveSupport", Module.new) unless defined?(ActiveSupport)
      ActiveSupport.define_singleton_method(:parallelize_test_databases) { flag }
    end

    # Rails 8.0's Parallelization has after-fork hooks only.
    it "forks on a Rails with no before-fork hooks" do
      par = Module.new
      par.define_singleton_method(:after_fork_hooks) { [->(_i) {}] }
      stub_const("ActiveSupport::Testing::Parallelization", par)
      record("db/test.sqlite3")
      allow(ActiveRecord::Base).to(receive(:connection_handler).and_return(double(connection_pool_list: [])))
      expect { databases.before_fork }.not_to(raise_error)
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

    def shared(database = "app_test", adapter: "postgresql")
      record(database, adapter: adapter)
      allow(ActiveRecord::Base).to(receive(:connection_handler).and_return(double(connection_pool_list: [])))
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
      parent = instance_double(Kimera::Execution::ParentConnections, release!: nil)
      allow(Kimera::Execution::ParentConnections).to(receive(:new).and_return(parent))
      databases.before_fork
      expect(parent).to(have_received(:release!))
    end

    it "says nothing of one worker, which has the database to itself" do
      record("app_test", adapter: "postgresql")
      allow(ActiveRecord::Base).to(receive(:connection_handler).and_return(double(connection_pool_list: [])))
      described_class.new(jobs: 1, errors: errors).before_fork
      expect(errors.string).to(be_empty)
    end

    it "creates and loads each numbered database once, before the workers fork" do
      switch(false)
      record("app_test", adapter: "postgresql")
      numbered = instance_double(Kimera::Execution::NumberedDatabases, numbered?: true, prepare: nil)
      allow(Kimera::Execution::NumberedDatabases).to(receive(:new).and_return(numbered))
      2.times { databases.before_fork }
      expect(numbered).to(have_received(:prepare).with(1).once)
      expect(errors.string).to(be_empty)
    end

    it "moves a worker onto its numbered database when no Rails hook does" do
      parallelization
      numbered = instance_double(Kimera::Execution::NumberedDatabases, adopt: nil)
      allow(Kimera::Execution::NumberedDatabases).to(receive(:new).and_return(numbered))
      databases.after_fork(1)
      expect(numbered).to(have_received(:adopt).with(1))
    end
  end

  # K3-5: the parent's own idle session blocked a mirror's drop_current.
  describe Kimera::Execution::ParentConnections do
    def pools(handler)
      stub_const("ActiveRecord::Base", Class.new)
      allow(ActiveRecord::Base).to(
        receive_messages(
          connection_handler: handler,
          connection_db_config: config("pg", "t")
        )
      )
    end

    it "disconnects every pool the parent opened" do
      pool = double(disconnect!: nil)
      pools(double(each_connection_pool: [pool]))
      described_class.new.release!
      expect(pool).to(have_received(:disconnect!))
    end

    it "reads the pools of Rails before 7.1 too" do
      pool = double(disconnect!: nil)
      pools(double(connection_pool_list: [pool]))
      described_class.new.release!
      expect(pool).to(have_received(:disconnect!))
    end

    it "keeps an in-memory database's connection, which holds its schema" do
      pool = double(disconnect!: nil)
      record(":memory:")
      allow(ActiveRecord::Base).to(receive(:connection_handler).and_return(double(each_connection_pool: [pool])))
      described_class.new.release!
      expect(pool).not_to(have_received(:disconnect!))
    end

    it "does nothing without Active Record, and survives a pool that will not let go" do
      expect { described_class.new.release! }.not_to(raise_error)
      pools(
        double(
          each_connection_pool: [
            double.tap do |pool|
              allow(pool).to(receive(:disconnect!).and_raise("busy"))
            end
          ]
        )
      )
      expect { described_class.new.release! }.not_to(raise_error)
    end
  end

  describe Kimera::Execution::NumberedDatabases do
    subject(:numbered) { described_class.new(errors: errors) }

    let(:errors) { StringIO.new }

    def rails(names, env = ENV)
      configurations =
        Class.new do
          define_method(:initialize) do |*|
            @named =
              names.call(env.fetch("TEST_ENV_NUMBER", nil)).map do |db|
                Struct.new(:name, :database).new("primary", db)
              end
          end
          define_method(:configs_for) do |env_name:, name: nil|
            named = env_name == "test" ? @named : []
            name ? named.first : named
          end
        end
      stub_const("ActiveRecord::DatabaseConfigurations", configurations)
      stub_const("ActiveRecord::ConnectionHandling::DEFAULT_ENV", -> { "test" })
      base = Class.new { class << self; attr_accessor :configurations; end }
      base.configurations = configurations.new
      allow(base).to(receive(:establish_connection))
      stub_const("ActiveRecord::Base", base)
      stub_const("Rails", double(application: double(config: double(database_configuration: {}))))
    end

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
      tasks = double(reconstruct_from_schema: nil)
      stub_const("ActiveRecord::Tasks::DatabaseTasks", tasks)
      numbered.prepare(2)
      expect(tasks).to(have_received(:reconstruct_from_schema).with(having_attributes(database: "app_test3")))
    end

    it "says which worker's database it could not create" do
      rails(->(number) { ["app_test#{number}"] })
      tasks = double
      allow(tasks).to(receive(:reconstruct_from_schema).and_raise(RuntimeError, "denied"))
      stub_const("ActiveRecord::Tasks::DatabaseTasks", tasks)
      numbered.prepare(1)
      expect(errors.string).to(eq("kimera: could not create the database for worker 1 (RuntimeError: denied)\n"))
    end

    it "reconnects a worker to its own database, leaving TEST_ENV_NUMBER as it found it" do
      rails(->(number) { ["app_test#{number}"] })
      numbered.adopt(1)
      expect(ActiveRecord::Base).to(have_received(:establish_connection))
      expect(ENV.key?("TEST_ENV_NUMBER")).to(be(false))
      expect(ActiveRecord::Base.configurations.configs_for(env_name: "test").map(&:database)).to(eq(["app_test2"]))
    end

    it "restores a TEST_ENV_NUMBER it found set, and reads the suite's own environment", :aggregate_failures do
      env = { "TEST_ENV_NUMBER" => "7" }
      rails(->(number) { ["app_test#{number}"] }, env)
      described_class.new(errors: errors, env: env).adopt(1)
      expect(env).to(eq("TEST_ENV_NUMBER" => "7"))
      expect(ActiveRecord::Base).to(have_received(:establish_connection))
      bare = {}
      rails(->(number) { ["app_test#{number}"] }, bare)
      described_class.new(errors: errors, env: bare).adopt(1)
      expect(bare).to(eq({}))
      expect(ActiveRecord::Base).to(have_received(:establish_connection))
      stub_const("ActiveRecord::ConnectionHandling::DEFAULT_ENV", -> { "development" })
      expect(described_class.new(errors: errors).numbered?).to(be(false))
    end

    it "stays on the parent's database when the name does not change" do
      rails(->(_number) { ["app_test"] })
      numbered.adopt(1)
      expect(ActiveRecord::Base).not_to(have_received(:establish_connection))
    end
  end

  describe Kimera::Execution::MirrorDatabase do
    it "renames a mirror's database before Rails 8.1, never an in-memory one" do
      calls = []
      parallelization(after: ->(slot) { calls << slot })
      record("db/test.sqlite3")
      mirror = described_class.new(3)
      allow(mirror).to(receive(:require))
      mirror.adopt
      record(":memory:")
      mirror.adopt
      expect(calls).to(eq([3]))
    end
  end

  it "hands each concurrent mirror its own TEST_ENV_NUMBER" do
    child = Kimera::Execution::IsolatedPlan::ChildCommand.new(framework: "rspec", test_files: [])
    environment =
      lambda do |slot|
        Dir.mktmpdir do |dir|
          child.command(dir, child.request([], slot: slot), ledger: File.join(dir, "l"), paths: []).first
        end
      end
    expect(environment.call(1)).to(eq("KIMERA" => "1", "TEST_ENV_NUMBER" => "2"))
    expect(environment.call(nil)).to(eq("KIMERA" => "1"))
  end

  it "names a database another session holds when a mirror cannot drop it" do
    held = Kimera::Execution::BaselineFailure::Mirror.new("PG::ObjectInUse: database is being accessed", "  hint")
    plain = Kimera::Execution::BaselineFailure::Mirror.new("failing: t1", "  hint")
    expect(held.to_s).to(end_with(Kimera::Execution::BaselineFailure::Mirror::HELD))
    expect(plain.to_s).to(end_with("  hint"))
  end
end
