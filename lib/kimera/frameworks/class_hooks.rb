# frozen_string_literal: true

require_relative "../support/test_exit"

module Kimera
  module Frameworks
  end
end

class Kimera::Frameworks::ClassHooks
  def initialize(klass)
    @klass = klass
    @failures = []
  end

  def test(name) = run { @klass.new(name).extend(Kimera::TestExit::Test).run }

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
