# frozen_string_literal: true

require_relative "../support/test_exit"

module Kimera
  module Frameworks
  end
end

# Runs one Minitest test inside its class's info handler, as Minitest's own
# runner does, so class-level hooks (minitest-hooks' before_all/after_all)
# run around it; a hook's failure, reported to the handler, is the result.
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
