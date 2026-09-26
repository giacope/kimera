# frozen_string_literal: true

require_relative "../results/result"
require_relative "../self_protection"

module Kimera
  module Execution
  end
end

class Kimera::Execution::Verdicts
  def initialize(registry)
    @registry = registry
  end

  def safe?(id)
    point(id).safe?
  end

  def reloadable?(id)
    !point(id).body?
  end

  def reclassify!(results)
    results.each { |id, result| reclassify(results, id, result) }
  end

  def parse(message)
    id = message["id"]
    Kimera::MutantResult.new(
      mutant_id: id, status: message["status"].to_sym, file: path(id),
      duration: message["ms"], failing_tests: message["fails"], covering_tests: message["cover"]
    )
  end

  def timeout(id, duration)
    Kimera::MutantResult.new(
      mutant_id: id, status: :timeout, file: path(id),
      duration: duration, detail: "hard watchdog timeout"
    )
  end

  def unjudged(id, detail)
    Kimera::MutantResult.new(mutant_id: id, status: :harness_error, file: path(id), detail: detail)
  end

  def quarantine(id)
    Kimera::MutantResult.new(mutant_id: id, status: :isolated_only, file: path(id), detail: point(id).unsafe_reason)
  end

  def point(id)
    @registry.index[id] || Kimera::MutationPoint::NONE
  end

  def path(id)
    point(id).file
  end

  private

  def reclassify(results, id, result)
    return unless suspect?(result)
    results[id] = result.isolated(detail(result.status))
  end

  def suspect?(result)
    Kimera::Status::SELF_SUSPECT.include?(result.status) && harness?(result)
  end

  def harness?(result)
    Kimera::SelfProtection.critical?(result.file)
  end

  def detail(status)
    "#{status == :survived ? "unfalsifiable warm survivor" : "self-crash"} in the in-process runner " \
      "(warm #{status}); evaluate with --isolated"
  end
end
