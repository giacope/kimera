# frozen_string_literal: true

require_relative "last_words"

module Kimera
  module Execution
    module SignalGuard
      Failure =
        Data.define(:test_id, :words) do
          def passed? = false

          def failures = { test_id => words }
        end

      module_function

      def run(test_id)
        yield
      rescue SignalException => error
        raise if error.is_a?(Interrupt)
        Failure.new(test_id, Kimera::Execution::LastWords.new(error).to_s)
      end
    end
  end
end
