# frozen_string_literal: true

module Kimera
  module Execution
  end
end

# An in-memory SQLite database lives only in the process that opened it: a
# fork inherits a private copy holding the schema the suite loaded, while a
# new connection (or a renamed one) starts empty. sqlite3 2.x closes every
# writable handle a fork inherits, and Active Record discards inherited pools;
# an in-memory database is no file two processes could corrupt, so kimera's
# forks keep it (SPARED, INHERITED).
class Kimera::Execution::MemoryDatabases
  NAMES = /\A(?::memory:|file::memory:)|[?&]mode=memory\b/
  NAMED = ->(config) { config.adapter.to_s.start_with?("sqlite") && config.database.to_s.match?(NAMES) }
  HELD =
    lambda do |handle|
      handle.weakref_alive? && !handle.closed? && handle.filename.to_s.empty?
    rescue StandardError
      false
    end

  INHERITED =
    Module.new do
      define_method(:discard_pool!) { NAMED.call(db_config) ? nil : super() }
    end

  SPARED =
    Module.new do
      define_method(:discard) do
        handles = instance_variable_get(:@databases)
        kept = handles.select(&HELD)
        handles.reject! { |handle| kept.any? { |spared| spared.__id__ == handle.__id__ } }
        super()
      ensure
        handles&.concat(kept.to_a)
      end
    end

  def initialize(record = (ActiveRecord::Base if defined?(ActiveRecord::Base)))
    @record = record
  end

  def current?
    !@record.nil? && NAMED.call(@record.connection_db_config)
  rescue StandardError
    false
  end
end
