# frozen_string_literal: true

module Kimera
  module Execution
  end
end

module Kimera::Execution::MemoryDatabases
  INHERITED =
    Module.new do
      define_method(:discard_pool!) do
        config = db_config
        config.adapter.to_s.start_with?("sqlite") && config.database.to_s == ":memory:" ? nil : super()
      end
    end
end
