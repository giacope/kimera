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
    def build(registry:, adapter:, root: ".", attribution: Kimera::Execution::OpenAttribution.new)
      base = "#{File.expand_path(root)}/"
      locate = ->(test) { File.expand_path(adapter.test_file(test).to_s).delete_prefix(base) }
      new(registry: registry, attribution: attribution, locate: locate)
    end

    def from_rules(rules, **) = build(**, attribution: Kimera::Execution::Attribution.new(rules))
  end

  def initialize(registry:, attribution: Kimera::Execution::OpenAttribution.new, flaky: [], locate: ->(_test) { "" })
    @registry = registry
    @attribution = attribution
    @flaky = flaky.to_set
    @locate = locate
  end

  def flag!(tests) = @flaky.merge(tests)

  def active? = @attribution.strict? || @flaky.any?

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
    steady.empty? ? unsteady(id, file, tests) : foreign(id, file, steady)
  end

  private

  def eligible?(test, file)
    return false if @flaky.include?(test)
    @attribution.admits?(file.to_s) { located[test] ||= @locate.call(test).to_s }
  end

  def located = @_located ||= {}

  def unsteady(id, file, tests)
    Kimera::MutantResult.new(mutant_id: id, file: file, status: :no_coverage, detail: "#{UNSTEADY}#{tests.join(", ")}")
  end

  def foreign(id, file, tests)
    Kimera::MutantResult.new(
      mutant_id: id, file: file, status: :uncovered_by_unit, covering_tests: tests,
      detail: "reached only by other units' tests (attribution: unit); none of its own tests " \
        "(#{@attribution.expected(file.to_s).join(", ")}, or a unit_tests rule) runs it"
    )
  end
end
