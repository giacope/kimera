# frozen_string_literal: true

require "json"
require "timeout"
require_relative "../results/result"
require_relative "../runtime"
require_relative "isolation"

class Kimera::Execution::Shift
  MODES = { true => :recheck }.freeze
  Channel =
    Data.define(:requests, :responses) do
      def each_request
        while (line = requests.gets)
          break unless yield(line, responses)
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

  def evaluate(id, mode = :warm)
    safely(Subject.new(id, @registry.index[id]&.file), mode)
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
      adapter: @adapter, isolation: isolation, killers: kind::KillerMemory.new, deadline: kind::Deadline.new(timeout)
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
    request = JSON.parse(line)
    return if process(request["id"], responses, history, index, MODES.fetch(request["recheck"], :warm)).is_a?(Suspect)
    emit(responses, t: "ready")
    index + 1
  end

  def safely(subject, mode)
    tests = available(subject.id)
    return subject.verdict(:no_coverage) if tests.empty?
    outcome(subject, tests, mode)
  rescue StandardError, ScriptError => error
    error(subject, error)
  end

  def error(subject, error)
    message = error.message
    return subject.verdict(:timeout, duration: timeout, detail: message) if error.is_a?(Timeout::Error)
    subject.verdict(:error, detail: "#{error.class}: #{message}")
  end

  def outcome(subject, tests, mode)
    started = monotonic
    outcome = attempt.run(subject.id, tests, mode)
    return outcome.ruling(subject) if outcome.is_a?(Suspect)
    subject.judged(outcome, tests, monotonic - started)
  end

  def process(id, io, history, index, mode = :warm)
    result = evaluate(id, mode)
    emit(io, **result.message)
    history << id if result.killed?
    leaks.check(io, history, index) unless result.is_a?(Suspect)
    result
  end

  def available(id)
    return @adapter.test_ids unless @coverage
    @coverage.fetch(id) { @coverage.fetch(id.to_s, []) }
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
require_relative "shift/subject"
require_relative "shift/suspect"
