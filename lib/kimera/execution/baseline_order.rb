# frozen_string_literal: true

require_relative "zygote"

module Kimera
  module Execution
  end
end

class Kimera::Execution::BaselineOrder
  def initialize(baseline)
    @baseline = baseline
  end

  def of(failed, zygote = Kimera::Execution::Zygote.new)
    passed = failed - Array(@baseline.sequence(zygote)["failed_ids"])
    passed.reject { |test| zygote.call { @baseline.alone?(test) } }
  rescue Kimera::Execution::Zygote::Died, Kimera::Execution::Zygote::Raised, Timeout::Error
    []
  end
end
