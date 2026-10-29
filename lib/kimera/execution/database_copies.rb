# frozen_string_literal: true

require_relative "database_copies/postgres"
require_relative "database_copies/sqlite"
require_relative "memory_databases"

module Kimera
  module Execution
  end
end

class Kimera::Execution::DatabaseCopies
  ENGINES = {
    /postg/i => Kimera::Execution::DatabaseCopies::Postgres, /sqlite/i => Kimera::Execution::DatabaseCopies::Sqlite
  }.freeze

  def initialize(errors: $stderr, hooks: Kernel, engines: ENGINES)
    @errors = errors
    @hooks = hooks
    @engines = engines
  end

  def possible? = engines.any?

  def prepare(indexes)
    made = indexes.select { |index| attempt("copy", index) { engines.each { |engine| engine.copy(name(index)) } } }
    owner = Process.pid
    @hooks.at_exit { drop(made) if Process.pid == owner }
  end

  def adopt(index)
    return unless engines.any? { |engine| engine.exist?(name(index)) }
    config._database = name(index)
    ActiveRecord::Base.establish_connection(config)
  end

  private

  def drop(indexes)
    indexes.each { |index| attempt("drop the copy of", index) { engines.each { |engine| engine.remove(name(index)) } } }
  end

  def config = ActiveRecord::Base.connection_db_config

  def name(index) = "#{config.database}_#{index}"

  def engines
    return @_engines if defined?(@_engines)
    @_engines = defined?(ActiveRecord::Base) && !Kimera::Execution::MemoryDatabases.new.current? ? pick : []
  end

  def pick
    @engines.select { |pattern, _| config.adapter.to_s.match?(pattern) }.first(1).map { |(_, kind)| kind.new(config) }
  rescue StandardError
    []
  end

  def attempt(action, index)
    yield
    true
  rescue StandardError => error
    @errors.puts(
      "kimera: could not #{action} the test database #{config.database} for process #{index} " \
        "(#{error.class}: #{error.message}); it uses the parent's"
    )
    false
  end
end
