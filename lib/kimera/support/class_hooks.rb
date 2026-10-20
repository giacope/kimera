# frozen_string_literal: true

module Kimera
end

class Kimera::ClassHooks
  def initialize(klass)
    @klass = klass
    @failures = []
  end

  def run
    result = nil
    @klass.with_info_handler(self) { result = yield }
    @failures.first || result
  end

  def record(result)
    @failures << result unless result.passed? || result.skipped?
  end

  def passed? = @failures.empty?
end
