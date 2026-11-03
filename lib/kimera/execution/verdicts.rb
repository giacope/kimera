# frozen_string_literal: true

require_relative "../results/result"

module Kimera
  module Execution
  end
end

class Kimera::Execution::Verdicts
  WIRE = { "id" => "mutant_id", "ms" => "duration", "fails" => "failing_tests", "cover" => "covering_tests" }.freeze

  def initialize(registry)
    @registry = registry
  end

  def parse(message)
    Kimera::MutantResult.from_h(message.transform_keys(WIRE).merge("file" => point(message["id"]).file))
  end

  def timeout(id, duration, stacks = [])
    Kimera::MutantResult.new(
      mutant_id: id, status: :timeout, file: point(id).file,
      duration: duration, detail: ["hard watchdog timeout", *stacks].join("\n")
    )
  end

  def unjudged(id, detail)
    Kimera::MutantResult.new(mutant_id: id, status: :harness_error, file: point(id).file, detail: detail)
  end

  def point(id)
    @registry.index[id] || Kimera::MutationPoint.none
  end
end
