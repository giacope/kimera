# frozen_string_literal: true

require_relative "../results/result"

module Kimera
  module Execution
  end
end

class Kimera::Execution::Verdicts
  WIRE = {
    "id" => "mutant_id", "ms" => "duration", "fails" => "failing_tests", "cover" => "covering_tests",
    "kills" => "killing_tests"
  }.freeze

  def initialize(registry)
    @registry = registry
  end

  def parse(message)
    Kimera::MutantResult.from_h(message.transform_keys(WIRE).merge("file" => @registry[message["id"]] { [] }.last))
  end

  def timeout(id, duration, stacks = [])
    result(id, status: :timeout, duration: duration, detail: ["hard watchdog timeout", *stacks].join("\n"))
  end

  def unjudged(id, detail) = result(id, status: :harness_error, detail: detail)

  def point(id)
    @registry.index[id] || Kimera::MutationPoint.none
  end

  private

  def result(id, **outcome) = Kimera::MutantResult.new(mutant_id: id, file: @registry[id] { [] }.last, **outcome)
end
