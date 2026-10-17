# frozen_string_literal: true

module Kimera
end

class Kimera::TestExit
  def initialize(error)
    @error = error
  end

  def failure
    SystemExit.new(@error.status, describe).tap { |failure| failure.set_backtrace(@error.backtrace) }
  end

  module Example
    private

    def with_around_example_hooks
      super
    rescue SystemExit => error
      set_exception(Kimera::TestExit.new(error).failure)
    end
  end

  module Test
    def capture_exceptions
      super do
        yield
      rescue SystemExit => error
        failures << ::Minitest::UnexpectedError.new(Kimera::TestExit.new(error).failure)
      end
    end
  end

  private

  def describe
    text = "exit(#{@error.status}) called from #{origin}"
    message = @error.message
    message == "exit" ? text : "#{text}: #{message}"
  end

  def origin = @error.backtrace.first.delete_prefix("#{Dir.pwd}#{File::SEPARATOR}")
end
