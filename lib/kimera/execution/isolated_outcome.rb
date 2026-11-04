# frozen_string_literal: true

module Kimera
  module Execution
  end
end

class Kimera::Execution::IsolatedOutcome
  def initialize(status, failing = nil, detail = nil)
    @status = status
    @failing = failing
    @detail = detail
  end

  def to_h = { status: status, failing_tests: failing, detail: detail }

  def killing(wanted) = wanted && status == :killed ? { killing_tests: failing } : {}

  def retried = outside? ? yield : self

  def cleared
    return self unless outside?
    control = yield
    control.survived? ? recurred : environmental(control)
  end

  def confirmed(kept) = survived? ? kept : yield(contradiction)

  def to_s
    return detail || "timed out" if timeout?
    named = Array(failing)
    return "failing: #{named.join(", ")}#{" (#{detail})" if detail}" if named.any?
    detail || "the test child failed without naming a test"
  end

  protected

  def survived? = status == :survived

  private

  attr_reader :status, :failing, :detail

  def outside? = status == :outside

  def timeout? = status == :timeout

  def recurred
    self.class.new(:killed, [], "#{detail} (it recurred with the mutant on; a fresh mirror without it runs clean)")
  end

  def environmental(control)
    self.class.new(:harness_error, nil, "#{detail}; without the mutant too (#{control}), so it is no kill")
  end

  def contradiction
    return "its tests time out in a fresh mirror without the mutant too (#{self}); raise --hard-timeout" if timeout?
    "its tests fail in a fresh mirror without the mutant too (#{self})"
  end
end

require_relative "isolated_outcome/ruling"
