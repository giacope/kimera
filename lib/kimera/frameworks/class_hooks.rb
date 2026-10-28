# frozen_string_literal: true

module Kimera
  module Frameworks
  end
end

class Kimera::Frameworks::ClassHooks
  Reporter =
    Struct.new(:results, :prepare) do
      def prerecord(*) = prepare.call

      def record(result)
        results << result
      end

      def passed? = results.all? { |result| result.passed? || result.skipped? }

      def reporters = []

      def synchronize = yield

      def outcome = results.find { |result| !result.passed? && !result.skipped? } || results.last
    end

  Serial =
    Data.define do
      def <<(work)
        klass, name, reporter = work
        reporter.prerecord(klass, name)
        reporter.record(klass.new(name).run)
      end
    end

  def initialize(klass)
    @klass = klass
  end

  def test(name, &prepare)
    reporter = Reporter.new([], prepare || proc {})
    serially { suite(reporter, /\A#{Regexp.escape(name)}\z/) }
    reporter.outcome
  end

  private

  def suite(reporter, only)
    options = { include: only, filter: only }
    @klass.respond_to?(:run_suite) ? @klass.run_suite(reporter, options) : @klass.run(reporter, options)
  end

  def serially
    executor = Minitest.parallel_executor
    Minitest.parallel_executor = Serial.new
    yield
  ensure
    Minitest.parallel_executor = executor
  end
end
