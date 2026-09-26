# frozen_string_literal: true

require "json"
require "timeout"
require_relative "../results/result"
require_relative "../runtime"
require_relative "isolation"

class Kimera::Execution::Shift
  Subject = Struct.new(:id, :file)
  Channel =
    Data.define(:requests, :responses) do
      def each_request
        while (line = requests.gets)
          yield(line, responses)
        end
      end
    end

  def initialize(adapter:, registry:, coverage: nil, **options)
    @adapter = adapter
    @registry = registry
    @coverage = coverage
    @options = options
  end

  def serve(requests, responses)
    listen(Channel.new(requests, responses))
    emit(responses, t: "done")
  ensure
    Kimera::Runtime.active = nil
  end

  def coverage(requests, responses) = channel.serve(requests, responses)

  def run(ids, io)
    history = []
    ids.each_with_index { |id, index| process(id, io, history, index) }
    emit(io, t: "done")
  ensure
    Kimera::Runtime.active = nil
  end

  def evaluate(id)
    safely(Subject.new(id, @registry.index[id]&.file))
  ensure
    Kimera::Runtime.active = nil
    isolation.reset!
  end

  private

  def isolation = @_isolation ||= @options.fetch(:isolation) { Kimera::Execution::Isolation.new }

  def timeout = @options.fetch(:soft_timeout, 5.0)

  def attempt
    kind = self.class
    @_attempt ||= kind::Attempt.new(
      adapter: @adapter, isolation: isolation, killers: kind::KillerMemory.new, timeout: timeout
    )
  end

  def leaks = @_leaks ||= self.class::LeakGuard.new(@options.fetch(:leak_every, 10)) { |id| evaluate(id) }

  def channel = @_channel ||= self.class::CoverageChannel.new(@adapter)

  def listen(connection)
    history = []
    index = 0
    connection.each_request { |line, responses| index = step(line, responses, history, index) }
  end

  def step(line, responses, history, index)
    process(JSON.parse(line)["id"], responses, history, index)
    emit(responses, t: "ready")
    index + 1
  end

  def safely(subject)
    tests = available(subject.id)
    return result(subject, :no_coverage) if tests.empty?
    outcome(subject, tests)
  rescue StandardError, ScriptError => error
    error(subject, error)
  end

  def error(subject, error)
    return result(subject, :timeout, timeout) if error.is_a?(Timeout::Error)
    result(subject, :error, detail: "#{error.class}: #{error.message}")
  end

  def outcome(subject, tests)
    started = monotonic
    outcome = attempt.run(subject.id, tests)
    result(subject, classify(outcome), monotonic - started, failing(outcome), tests)
  end

  def process(id, io, history, index)
    result = evaluate(id)
    emit(io, **result.message)
    history << id if result.killed?
    leaks.check(io, history, index)
  end

  def classify(outcome)
    !outcome || outcome.passed? ? :survived : :killed
  end

  def failing(outcome) = outcome&.failed_ids

  def available(id)
    return @adapter.test_ids unless @coverage
    @coverage.fetch(id) { @coverage.fetch(id.to_s, []) }
  end

  def result(subject, status, duration = nil, fails = nil, cover = nil, detail: nil)
    Kimera::MutantResult.new(
      mutant_id: subject.id, status: status, file: subject.file,
      duration: duration, failing_tests: fails,
      covering_tests: cover, detail: detail
    )
  end

  def emit(io, **message)
    io.puts(JSON.generate(message))
  end

  def monotonic
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end

require_relative "shift/attempt"
require_relative "shift/coverage_channel"
require_relative "shift/killer_memory"
require_relative "shift/leak_guard"
