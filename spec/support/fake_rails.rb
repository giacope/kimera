# frozen_string_literal: true

module FakeRails
  Config = Struct.new(:adapter, :database, :name) { alias_method(:_database=, :database=) }

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

  class Configurations
    def initialize(configs)
      @configs = configs
    end

    def configs_for(env_name:, name: nil)
      found = env_name == "test" ? @configs : []
      name ? found.find { |config| config.name == name } : found
    end
  end

  Application =
    Struct.new(:database_configuration) do
      def application = self

      def config = self
    end

  Handle =
    Struct.new(:filename, :closed, :alive) do
      def closed? = closed

      def weakref_alive? = alive
    end

  class Pools
    def initialize(pools = [])
      @pools = pools
    end

    def each_connection_pool = @pools.each
  end

  class ListedPools
    def initialize(pools = [])
      @pools = pools
    end

    def connection_pool_list = @pools
  end

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

  class Pool
    def disconnect! = (@disconnected = true)

    def disconnected? = @disconnected == true
  end

  class BusyPool
    def disconnect! = raise(RuntimeError, "busy")
  end

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
