# frozen_string_literal: true

module Kimera
  module Execution
  end
end

class Kimera::Execution::DatabaseCopies; end

# Copies a PostgreSQL database with CREATE DATABASE ... TEMPLATE, which needs
# no other session on the template: the parent has disconnected, and no
# worker or mirror runs yet. Active Record's own database tasks connect to the
# server's maintenance database to create and drop; the parent's connection
# settings are restored after, unconnected.
class Kimera::Execution::DatabaseCopies::Postgres
  EXISTS = "SELECT 1 FROM pg_database WHERE datname = %s"

  def initialize(config)
    @config = config
  end

  def copy(name)
    tasks(name, template: @config.database).then do |copied|
      copied.drop
      copied.create
    end
  ensure
    ActiveRecord::Base.establish_connection(@config)
  end

  def exist?(name) = ActiveRecord::Base.connection_pool.with_connection { |connection| listed?(connection, name) }

  def remove(name)
    tasks(name).drop
  ensure
    ActiveRecord::Base.establish_connection(@config)
  end

  private

  def listed?(connection, name) = !connection.select_value(format(EXISTS, connection.quote(name))).nil?

  def tasks(name, **settings)
    settings = @config.configuration_hash.merge(database: name, **settings)
    config = ActiveRecord::DatabaseConfigurations::HashConfig.new(@config.env_name, "#{@config.name}_copy", settings)
    ActiveRecord::Tasks::PostgreSQLDatabaseTasks.new(config)
  end
end
