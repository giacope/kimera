# frozen_string_literal: true

require_relative "../results/result"
require_relative "attribution"

module Kimera
  module Execution
  end
end

class Kimera::Execution::TestFilter
  UNSTEADY = "covered only by flaky test(s), which never kill: "

  class << self
    def build(registry:, rules: nil, locate: ->(_test) { "" })
      new(registry: registry, attribution: rules && Kimera::Execution::Attribution.new(rules), locate: locate)
    end
  end

  def initialize(registry:, attribution: nil, flaky: [], locate: ->(_test) { "" })
    @registry = registry
    @attribution = attribution
    @flaky = flaky.to_set
    @locate = locate
    @files = {}
    @flakes = nil
  end

  attr_reader :flakes

  def flag!(record)
    @flakes = record
    @flaky.merge(record.flaky)
  end

  def active? = !@attribution.nil? || @flaky.any?

  def keep(file, tests) = tests.select { |test| eligible?(test, file) }

  def screen(coverage)
    coverage.each_with_object([{}, {}]) do |(id, tests), (kept, settled)|
      verdict = settle(id, tests)
      verdict ? settled[id] = verdict : kept[id] = keep(@registry.index[id]&.file, tests)
    end
  end

  def settle(id, tests)
    file = @registry.index[id]&.file
    return if tests.empty? || keep(file, tests).any?
    steady = tests.reject { |test| @flaky.include?(test) }
    Kimera::MutantResult.new(mutant_id: id, file: file, **(steady.empty? ? unsteady(tests) : foreign(file, steady)))
  end

  private

  def eligible?(test, file)
    return false if @flaky.include?(test)
    @attribution.nil? || @attribution.own?(@files[test] ||= @locate.call(test), file.to_s)
  end

  def unsteady(tests) = { status: :no_coverage, detail: "#{UNSTEADY}#{tests.join(", ")}" }

  def foreign(file, tests)
    {
      status: :uncovered_by_unit, covering_tests: tests,
      detail: "reached only by other units' tests (attribution: unit); none of its own tests " \
        "(#{@attribution.expected(file.to_s).join(", ")}, or a unit_tests rule) runs it"
    }
  end
end
