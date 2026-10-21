# frozen_string_literal: true

require "json"
require "timeout"
require_relative "../results/result"
require_relative "../runtime"
require_relative "isolation"
require_relative "patience"
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
    tally(safely(Subject.new(id, @registry.index[id]&.file)))
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
    pace = Kimera::Execution::Pace.new(@options.fetch(:timings, {}))
    @_attempt ||= kind::Attempt.new(
      probe: probe, isolation: isolation, killers: kind::KillerMemory.new(pace), zygote: zygote
    )
  end

  def tally(result)
    return result unless @options[:quality] && result.killed?
    killers = census.killers(result.mutant_id, available(result.mutant_id), Array(result.failing_tests))
    result.tap { |found| found.killing_tests = killers }
  end

  def census
    @_census ||= self.class::Census.new(probe: probe, isolation: isolation, zygote: zygote)
  end

  def probe
    kind = self.class
    beat = @options.fetch(:pulse, kind::Deadline::SILENT)
    kind::Probe.new(@adapter, kind::Deadline.build(timeout, patience: patience, beat: beat, **@options.slice(:budget)))
  end

  def patience = Kimera::Execution::Patience.new(timeout, **@options.slice(:timings, :ceiling))

  def channel = @_channel ||= self.class::CoverageChannel.new(@adapter, zygote: zygote)

  def step(line, responses)
    emit(responses, **evaluate(JSON.parse(line)["id"]).message)
    emit(responses, t: "ready")
  end

  def safely(subject)
    covered(subject)
  rescue Kimera::Execution::Zygote::Died
    raise
  rescue StandardError, ScriptError => error
    subject.crashed(error, timeout)
  end

  def covered(subject)
    tests = available(subject.id)
    return subject.verdict(:no_coverage) if tests.empty?
    outcome(subject, tests)
  end

  def outcome(subject, tests)
    started = monotonic
    outcome = attempt.run(subject.id, tests) || unmasked(subject.id, tests)
    subject.judged(outcome, tests, monotonic - started)
  end

  def unmasked(id, tests)
    return unless @options[:confirm]
    pace = Kimera::Execution::Pace.new(@options.fetch(:timings, {}))
    self.class::Unmask.new(attempt, pace).run(id, tests)
  end

  def available(id)
    return @adapter.test_ids unless @coverage
    @coverage.fetch(id) { @coverage.fetch(id.to_s, []) }
  end

  def emit(io, **message)
    io.puts(JSON.generate(message))
  end

  def monotonic(reading = Process.clock_gettime(Process::CLOCK_MONOTONIC)) = reading
end

require_relative "shift/attempt"
require_relative "shift/census"
require_relative "shift/coverage_channel"
require_relative "shift/killer_memory"
require_relative "shift/subject"
require_relative "shift/suspect"
require_relative "shift/unmask"
