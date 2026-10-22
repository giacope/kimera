# frozen_string_literal: true

require_relative "database_copies/postgres"
require_relative "database_copies/sqlite"
require_relative "memory_databases"

module Kimera
  module Execution
  end
end

# A suite that prepares its test database as it loads (thredded migrates it)
# leaves no schema file for Rails' per-worker hook to load. Each warm worker
# and isolated mirror past the first then gets a copy of the database the
# parent prepared, made after the parent disconnected and named
# <database>_<n>: PostgreSQL copies it with CREATE DATABASE ... TEMPLATE, and
# an SQLite file is copied. A process takes its copy only when it exists, and
# the copies are dropped when the run ends. Other adapters cannot copy.
class Kimera::Execution::DatabaseCopies
  ENGINES = {
    /postg/i => Kimera::Execution::DatabaseCopies::Postgres, /sqlite/i => Kimera::Execution::DatabaseCopies::Sqlite
  }.freeze

  def initialize(errors: $stderr, hooks: Kernel)
    @errors = errors
    @hooks = hooks
  end

  def possible? = !engine.nil?

  def prepare(indexes)
    made = indexes.select { |index| attempt("copy", index) { engine.copy(name(index)) } }
    owner = Process.pid
    @hooks.at_exit { drop(made) if Process.pid == owner }
  end

  def adopt(index)
    copy = engine && name(index)
    return unless copy && engine.exist?(copy)
    config._database = copy
    ActiveRecord::Base.establish_connection(config)
  end

  private

  def drop(indexes) = indexes.each { |index| attempt("drop the copy of", index) { engine.remove(name(index)) } }

  def config = ActiveRecord::Base.connection_db_config

  def name(index) = "#{config.database}_#{index}"

  def engine
    return @_engine if defined?(@_engine)
    @_engine = (pick if defined?(ActiveRecord::Base) && !Kimera::Execution::MemoryDatabases.new.current?)
  end

  def pick
    ENGINES.find { |pattern, _| config.adapter.to_s.match?(pattern) }&.last&.new(config)
  rescue StandardError
    nil
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
