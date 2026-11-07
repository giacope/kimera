# frozen_string_literal: true

require_relative "isolated"
require_relative "unmeasured"

class Kimera::Execution::Survey
  def initialize(options, adapter)
    @options = options
    @adapter = adapter
  end

  def coverage = @options.fetch(:coverage) { Kimera::Execution::Unmeasured.new(@adapter) }

  def isolated(executions = Kimera::Execution::IsolatedExecution, **) = executions.new(coverage:, timings:, **)

  def noted(report) = report.annotate(flaky: @options[:flakes]&.to_h)

  private

  def timings = @options.fetch(:timings, {})
end
