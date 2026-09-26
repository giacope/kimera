# frozen_string_literal: true

require "stringio"
require_relative "../error"
require_relative "../runtime"
require_relative "baseline_failure"
require_relative "null_progress"

class Kimera::Execution::BaselinePass
  Measured = Struct.new(:coverage, :irrelevant, keyword_init: true)
  Tally = Struct.new(:coverage, :failures, :irrelevant)

  def initialize(adapter:, registry:, progress: Kimera::Execution::NullProgress)
    @adapter = adapter
    @registry = registry
    @progress = progress
    @messages = {}
  end

  def measure!
    settle { serial }
  end

  def parallel!(&)
    settle { dispatch(&) }
  end

  def check!
    Kimera::Runtime.active = nil
    outcome = quietly { @adapter.run(@adapter.test_ids) }
    return if outcome.passed?
    @messages = outcome.failures
    failure!(outcome.failed_ids)
  end

  private

  def settle
    @progress.start(@adapter.test_ids.size, "baseline")
    yield
    report
  ensure
    @progress.finish
  end

  def tally = @_tally ||= Tally.new(Hash.new { |h, k| h[k] = [] }, [], [])

  def report
    failures = tally.failures
    failure!(failures) unless failures.empty?
    Measured.new(coverage: tally.coverage, irrelevant: tally.irrelevant)
  end

  def serial
    ledger = Kimera::Runtime.start!
    @adapter.test_ids.each { |test_id| attempt(ledger, test_id) }
  ensure
    Kimera::Runtime.stop!(ledger)
  end

  def attempt(ledger, test_id)
    Kimera::Runtime.active = nil
    Kimera::Runtime.clear!(ledger)
    record(test_id, quietly { @adapter.run([test_id]) }, Kimera::Runtime.drain!(ledger))
  end

  def record(test_id, outcome, touched)
    touched.each { |id| tally.coverage[id] << test_id }
    bank(test_id, touched, message: outcome.failures[test_id]) unless outcome.passed?
    @progress.tick
  end

  def dispatch
    yield(resolve: resolve, lost: loss)
  end

  def resolve
    ->(message) { receive(message) }
  end

  def receive(message)
    touched = message["touched"]
    test_id = message["id"]
    touched.each { |id| tally.coverage[id] << test_id }
    bank(test_id, touched, message: message["failure"]) unless message["passed"]
    @progress.tick
  end

  def loss
    method(:lost)
  end

  def lost(test_id, _reason)
    tally.failures << test_id
    @progress.tick
  end

  def bank(test_id, touched, message: nil)
    @messages[test_id] = message
    bucket(touched) << test_id
  end

  def bucket(touched)
    Array(touched).any? { |id| @registry.index.key?(id) } ? tally.failures : tally.irrelevant
  end

  def quietly
    swap = [$stdout, $stderr]
    silence
    yield
  ensure
    $stdout, $stderr = swap
  end

  def silence
    $stdout = StringIO.new
    $stderr = StringIO.new
  end

  def failure!(failed)
    command = @adapter.reproduce(failed.first(Kimera::Execution::BaselineFailure::MAX_DETAILS))
    raise(Kimera::Execution::BaselineFailure.build(failed, @messages, command))
  end
end
