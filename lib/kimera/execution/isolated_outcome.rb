# frozen_string_literal: true

module Kimera
  module Execution
  end
end

class Kimera::Execution::IsolatedOutcome
  attr_reader :status, :failing, :detail

  def initialize(status, failing = nil, detail = nil)
    @status = status
    @failing = failing
    @detail = detail
  end

  def killers(wanted) = wanted && status == :killed ? failing : nil

  def outside? = status == :outside

  def recurred
    self.class.new(:killed, [], "#{detail} (it recurred with the mutant on; a fresh mirror without it runs clean)")
  end

  def environmental(control)
    self.class.new(:harness_error, nil, "#{detail}; without the mutant too (#{control.explain}), so it is no kill")
  end

  def timed(seconds)
    return self unless status == :timeout && !detail
    self.class.new(:timeout, failing, "timed out after #{seconds}s without a test finishing")
  end

  def contradiction
    return "its tests time out in a fresh mirror without the mutant too (#{explain}); raise --hard-timeout" if timeout?
    "its tests fail in a fresh mirror without the mutant too (#{explain})"
  end

  def timeout? = status == :timeout

  def explain
    return detail || "timed out" if timeout?
    named = Array(failing)
    return "failing: #{named.join(", ")}#{" (#{detail})" if detail}" if named.any?
    detail || "the test child failed without naming a test"
  end
end

require_relative "isolated_outcome/ruling"
