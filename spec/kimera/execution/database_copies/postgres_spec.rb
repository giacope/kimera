# frozen_string_literal: true

require "kimera/execution/database_copies"

RSpec.describe(Kimera::Execution::DatabaseCopies::Postgres) do
  subject(:engine) { described_class.new(config) }

  let(:config) do
    Struct.new(:env_name, :name, :database, :configuration_hash)
      .new("test", "primary", "app_test", { adapter: "postgresql", database: "app_test", host: "db" })
  end
  let(:log) { [] }
  let(:named) { [] }

  before do
    stub_const("ActiveRecord::Base", base(log))
    stub_const("ActiveRecord::DatabaseConfigurations::HashConfig", configs(named))
    stub_const("ActiveRecord::Tasks::PostgreSQLDatabaseTasks", tasks(log))
  end

  def base(sink, listed = nil)
    pool = self.pool(listed)
    Class.new do
      define_singleton_method(:establish_connection) { |db| sink << [:connect, db.database] }
      define_singleton_method(:connection_pool) { pool }
    end
  end

  def configs(sink)
    Struct.new(:env_name, :name, :configuration_hash) do
      define_method(:initialize) do |*settings|
        sink << settings.first(2)
        super(*settings)
      end
    end
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
    Struct.new(:connection) { def with_connection = yield(connection) }.new(connection)
  end

  it "drops a stale copy, creates it from the database as its template, and restores the parent's settings" do
    engine.copy("app_test_1")
    copied = { adapter: "postgresql", database: "app_test_1", host: "db", template: "app_test" }
    expect(log).to(eq([[:drop, copied], [:create, "app_test"], [:connect, "app_test"]]))
  end

  it "restores the parent's settings when the copy fails" do
    refusing = Class.new { def initialize(_config) = raise(RuntimeError) }
    stub_const("ActiveRecord::Tasks::PostgreSQLDatabaseTasks", refusing)
    expect { engine.copy("app_test_1") }.to(raise_error(RuntimeError).and(change(log, :size).by(1)))
  end

  it "names the copy apart from the parent's config" do
    engine.remove("app_test_1")
    expect(named).to(eq([%w[test primary_copy]]))
  end

  it "drops a copy, and restores the parent's settings" do
    engine.remove("app_test_1")
    expect(log).to(eq([[:drop, { adapter: "postgresql", database: "app_test_1", host: "db" }], [:connect, "app_test"]]))
  end

  it "finds a copy the server lists, and no other" do
    stub_const("ActiveRecord::Base", base(log, "app_test_1"))
    expect(%w[app_test_1 app_test_2].map { |name| engine.exist?(name) }).to(eq([true, false]))
  end
end
