# frozen_string_literal: true

# Stand-ins for the parts of Rails and Active Record that kimera's database
# handling reads, put in place of the real constants with stub_const.
module FakeRails
  # A database configuration, as connection_db_config and configs_for answer
  # one; a copy renames its database as Active Record's _database= does.
  Config = Struct.new(:adapter, :database, :name) { alias_method(:_database=, :database=) }

  # ActiveRecord::Base: its connection's configuration, the configurations, the
  # connection pools, its one connection, and each connection it was told to
  # establish.
  class Base
    attr_accessor :configurations
    attr_reader :connection_handler, :connection, :established

    def initialize(config, configurations: Configurations.new([config]), handler: Pools.new, connection: nil)
      @config = config
      @configurations = configurations
      @connection_handler = handler
      @connection = connection
      @established = []
    end

    def connection_db_config = @config

    def establish_connection(config = nil) = @established.push(config)
  end

  # ActiveRecord::DatabaseConfigurations: the configurations of the test
  # environment, by name.
  class Configurations
    def initialize(configs)
      @configs = configs
    end

    def configs_for(env_name:, name: nil)
      found = env_name == "test" ? @configs : []
      name ? found.find { |config| config.name == name } : found
    end
  end

  # Rails, as far as its application's database configuration.
  Application =
    Struct.new(:database_configuration) do
      def application = self

      def config = self
    end

  # An SQLite3 database handle, as SQLite3::ForkSafety holds it.
  Handle =
    Struct.new(:filename, :closed, :alive) do
      def closed? = closed

      def weakref_alive? = alive
    end

  # The connection pools, as the connection handler of Rails 7.1 and later
  # walks them.
  class Pools
    def initialize(pools = [])
      @pools = pools
    end

    def each_connection_pool = @pools.each
  end

  # The connection pools, as the connection handler of Rails before 7.1 lists them.
  class ListedPools
    def initialize(pools = [])
      @pools = pools
    end

    def connection_pool_list = @pools
  end

  # A connection to the test database: its adapter and tables, and what it
  # was told to run, in order; truncating raises +truncate+ when given.
  class Connection
    attr_reader :adapter_name, :tables, :said

    def initialize(adapter_name, tables, truncate: nil)
      @adapter_name = adapter_name
      @tables = tables
      @truncate = truncate
      @said = []
    end

    def execute(statement) = @said.push([:execute, statement])

    def truncate_tables(*tables)
      raise(@truncate) if @truncate
      @said.push([:truncate_tables, *tables])
    end
  end

  # A connection pool that knows whether it was disconnected.
  class Pool
    def disconnect! = (@disconnected = true)

    def disconnected? = @disconnected == true
  end

  # A connection pool whose connection is busy and will not let go.
  class BusyPool
    def disconnect! = raise(ActiveRecord::ExclusiveConnectionTimeoutError, "busy")
  end

  # ActiveRecord::Base before the suite establishes a connection.
  class Unconnected
    def connection_db_config = raise(ActiveRecord::ConnectionNotEstablished, "No connection pool")
  end

  # Active Record's errors that kimera rescues, put in place with stub_const
  # under their real names: the root of its errors, a connection the suite
  # never established, and a pool whose connection will not let go in time.
  def self.errors(example)
    root = Class.new(StandardError)
    example.stub_const("ActiveRecord::ActiveRecordError", root)
    example.stub_const("ActiveRecord::ConnectionNotEstablished", Class.new(root))
    example.stub_const("ActiveRecord::ExclusiveConnectionTimeoutError", Class.new(root))
  end

  # Active Record loaded, its errors with it, before the suite connects.
  def self.unconnected(example)
    errors(example)
    example.stub_const("ActiveRecord::Base", Unconnected.new)
  end

  # ActiveRecord::Tasks::DatabaseTasks: the schema dump each database loads
  # from (or the error working it out raises), and each database it rebuilt.
  class Tasks
    attr_reader :rebuilt

    def initialize(schema = nil, failure: nil)
      @schema = schema
      @failure = failure
      @rebuilt = []
    end

    def schema_dump_path(_config) = @failure ? raise(@failure) : @schema

    def reconstruct_from_schema(config) = @failure ? raise(@failure) : @rebuilt.push(config)
  end
end

# A Rails application that eager-loads, writing down how often, or raises the
# error it was given.
class FakeApplication
  attr_reader :eager_loads

  def initialize(failure = nil)
    @failure = failure
    @eager_loads = 0
  end

  def eager_load!
    raise(@failure) if @failure
    @eager_loads += 1
  end
end
