# frozen_string_literal: true

require "json"
require "timeout"
require_relative "../results/result"
require_relative "../runtime"
require_relative "isolation"
require_relative "zygote"

class Kimera::Execution::Shift
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
    Channel.new(requests, responses).each_request { |line, io| step(line, io) }
    emit(responses, t: "done")
  ensure
    Kimera::RUNTIME.active = nil
  end

  def coverage(requests, responses) = channel.serve(requests, responses)

  def run(ids, io)
    ids.each { |id| emit(io, **evaluate(id).message) }
    emit(io, t: "done")
  ensure
    Kimera::RUNTIME.active = nil
  end

  def evaluate(id)
    safely(Subject.new(id, @registry.index[id]&.file))
  ensure
    Kimera::RUNTIME.active = nil
    isolation.reset!
  end

  private

  def isolation = @_isolation ||= @options.fetch(:isolation) { Kimera::Execution::Isolation.new }

  def timeout = @options.fetch(:soft_timeout, 5.0)

  def zygote = @options.fetch(:zygote) { Kimera::Execution::Zygote.new }

  def attempt
    kind = self.class
    @_attempt ||= kind::Attempt.new(probe: probe, isolation: isolation, killers: kind::KillerMemory.new, zygote: zygote)
  end

  def probe
    kind = self.class
    beat = @options.fetch(:pulse, kind::Deadline::SILENT)
    kind::Probe.new(@adapter, kind::Deadline.build(timeout, beat: beat, **budget))
  end

  def budget = @options.slice(:budget)

  def channel = @_channel ||= self.class::CoverageChannel.new(@adapter, zygote: zygote)

  def step(line, responses)
    emit(responses, **evaluate(JSON.parse(line)["id"]).message)
    emit(responses, t: "ready")
  end

  def safely(subject)
    covered(subject)
  rescue StandardError, ScriptError => error
    raise if error.is_a?(Kimera::Execution::Zygote::Died)
    subject.crashed(error, timeout)
  end

  def covered(subject)
    tests = available(subject.id)
    return subject.verdict(:no_coverage) if tests.empty?
    outcome(subject, tests)
  end

  def outcome(subject, tests)
    started = monotonic
    outcome = attempt.run(subject.id, tests)
    return outcome.ruling(subject) if outcome.is_a?(Doubt)
    subject.judged(outcome, tests, monotonic - started)
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
require_relative "shift/subject"
require_relative "shift/suspect"
