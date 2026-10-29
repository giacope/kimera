# frozen_string_literal: true

require "stringio"

module Kimera
  module Execution
  end
end

class Kimera::Execution::StandardStreams
  def initialize(output = StringIO.new, errors = StringIO.new)
    @output = output
    @errors = errors
  end

  def quietly
    swap = [$stdout, $stderr]
    $stdout = @output
    $stderr = @errors
    yield
  ensure
    $stdout, $stderr = swap
  end

  def holding_errors
    original = $stderr
    $stderr = @errors
    yield.tap { original.write(@errors.string) }
  ensure
    $stderr = original
  end
end
