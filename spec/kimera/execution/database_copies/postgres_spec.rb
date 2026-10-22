# frozen_string_literal: true

require "kimera/execution/database_copies"

# Stand-ins for Active Record's base, its config class and its PostgreSQL
# tasks record each call in one log.
RSpec.describe(Kimera::Execution::DatabaseCopies::Postgres) do
  subject(:engine) { described_class.new(config) }

  let(:config) do
    Struct.new(:env_name, :name, :database, :configuration_hash)
      .new("test", "primary", "app_test", { adapter: "postgresql", database: "app_test", host: "db" })
  end
  let(:log) { [] }

  before do
    sink = log
    base = Class.new { define_singleton_method(:establish_connection) { |db| sink << [:connect, db.database] } }
    stub_const("ActiveRecord::Base", base)
    stub_const("ActiveRecord::DatabaseConfigurations::HashConfig", Struct.new(:env_name, :name, :configuration_hash))
    stub_const("ActiveRecord::Tasks::PostgreSQLDatabaseTasks", tasks(sink))
  end

  def tasks(sink)
    Struct.new(:config) do
      define_method(:drop) { sink << [:drop, config.configuration_hash] }
      define_method(:create) { sink << [:create, config.configuration_hash[:template]] }
    end
  end

  def pool(listed)
    connection = Struct.new(:listed) do
      def quote(name) = "'#{name}'"
      def select_value(sql) = (1 if sql == "SELECT 1 FROM pg_database WHERE datname = '#{listed}'")
    end.new(listed)
    pool = Struct.new(:connection) { def with_connection = yield(connection) }
    allow(ActiveRecord::Base).to(receive(:connection_pool).and_return(pool.new(connection)))
  end

  it "drops a stale copy, creates it from the database as its template, and restores the parent's settings" do
    engine.copy("app_test_1")
    copied = { adapter: "postgresql", database: "app_test_1", host: "db", template: "app_test" }
    expect(log).to(eq([[:drop, copied], [:create, "app_test"], [:connect, "app_test"]]))
  end

  it "restores the parent's settings when the copy fails" do
    allow(ActiveRecord::Tasks::PostgreSQLDatabaseTasks).to(receive(:new).and_raise(RuntimeError))
    expect { engine.copy("app_test_1") }.to(raise_error(RuntimeError).and(change(log, :size).by(1)))
  end

  it "names the copy apart from the parent's config" do
    allow(ActiveRecord::DatabaseConfigurations::HashConfig).to(receive(:new).and_call_original)
    engine.remove("app_test_1")
    expect(ActiveRecord::DatabaseConfigurations::HashConfig)
      .to(have_received(:new).with("test", "primary_copy", anything))
  end

  it "drops a copy, and restores the parent's settings" do
    engine.remove("app_test_1")
    expect(log).to(eq([[:drop, { adapter: "postgresql", database: "app_test_1", host: "db" }], [:connect, "app_test"]]))
  end

  it "finds a copy the server lists, and no other" do
    pool("app_test_1")
    expect(%w[app_test_1 app_test_2].map { |name| engine.exist?(name) }).to(eq([true, false]))
  end
end
