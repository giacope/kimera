# frozen_string_literal: true

module Kimera
  module Execution
  end
end

class Kimera::Execution::Tolerance
  def initialize(errors)
    @errors = errors
  end

  def attempt(failure)
    yield
  rescue StandardError => error
    @errors.puts("kimera: #{failure} (#{error.class}: #{error.message})")
  end
end
