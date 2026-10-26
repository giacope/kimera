# frozen_string_literal: true

require_relative "../exits/test_exit"

module Kimera
  module Frameworks
  end
end

class Kimera::Frameworks::ClassHooks
  Reporter =
    Struct.new(:failures) do
      def record(result)
        failures << result unless result.passed? || result.skipped?
      end

      def passed? = failures.empty?
    end

  def initialize(klass)
    @klass = klass
  end

  def test(name) = run { @klass.new(name).extend(Kimera::TestExit::Test).run }

  def run
    result = nil
    reporter = Reporter.new([])
    @klass.with_info_handler(reporter) { result = yield }
    reporter.failures.first || result
  end
end
