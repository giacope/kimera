# frozen_string_literal: true

module Kimera
end

module Kimera::TestExit
  module_function

  def failure(error)
    SystemExit.new(error.status, describe(error)).tap { |failure| failure.set_backtrace(error.backtrace) }
  end

  def describe(error)
    text = "exit(#{error.status}) called from #{origin(error)}"
    message = error.message
    message == "exit" ? text : "#{text}: #{message}"
  end

  def origin(error) = error.backtrace.first.delete_prefix("#{Dir.pwd}#{File::SEPARATOR}")

  module Example
    private

    def with_around_example_hooks
      super
    rescue SystemExit => error
      set_exception(Kimera::TestExit.failure(error))
    end
  end

  module Test
    def capture_exceptions
      super do
        yield
      rescue SystemExit => error
        failures << ::Minitest::UnexpectedError.new(Kimera::TestExit.failure(error))
      end
    end
  end
end
