# frozen_string_literal: true

require "json"
require "timeout"
require_relative "../results/result"
require_relative "../runtime"
require_relative "isolation"
require_relative "patience"
require_relative "unmeasured"
require_relative "zygote"

class Kimera::Execution::Shift
  class Channel
    def initialize(requests)
      @requests = requests
    end

    def ids = Enumerator.produce { @requests.gets }.lazy.take_while(&:itself).map { |line| JSON.parse(line)["id"] }
  end

  def initialize(adapter:, registry:, coverage: Kimera::Execution::Unmeasured.new(adapter), **options)
    @adapter = adapter
    @registry = registry
    @coverage = coverage
    @options = options
  end

  def serve(requests, responses) = judging(Channel.new(requests).ids, responses, { t: "ready" })

  def coverage(requests, responses) = channel.serve(requests, responses)

  def run(ids, io) = judging(ids, io)

  def evaluate(id)
    result, = judged(id, killers)
    result
  end

  private

  def judging(ids, io, *after)
    ids.reduce(killers) do |memory, id|
      result, memory = judged(id, memory)
      [result.message, *after].each { |message| emit(io, **message) }
      memory
    end
    emit(io, t: "done")
  end

  def judged(id, memory)
    result, memory = safely(id, Subject.new(id, @registry.index[id]&.file), memory)
    [tally(result), memory]
  ensure
    isolation.reset!
  end

  def killers
    pace = @options.fetch(:pace) { Kimera::Execution::Pace.new(@options.fetch(:timings, {})) }
    self.class::KillerMemory.new(pace)
  end

  def isolation = @_isolation ||= @options.fetch(:isolation) { Kimera::Execution::Isolation.new }

  def timeout = @options.fetch(:soft_timeout, 5.0)

  def zygote = @options.fetch(:zygote) { Kimera::Execution::Zygote.new }

  def attempt = @_attempt ||= staged(self.class::Attempt)

  def tally(result)
    return result unless @options[:quality] && result.killed?
    killers = census.killers(result.mutant_id, available(result.mutant_id), Array(result.failing_tests))
    result.tap { |found| found.killing_tests = killers }
  end

  def census = @_census ||= staged(self.class::Census)

  def staged(kind) = kind.new(probe: probe, isolation: isolation, zygote: zygote)

  def probe
    kind = self.class
    beat = @options.fetch(:pulse, kind::Deadline::SILENT)
    kind::Probe.new(@adapter, kind::Deadline.build(timeout, patience: patience, beat: beat, **@options.slice(:budget)))
  end

  def patience = Kimera::Execution::Patience.new(timeout, **@options.slice(:timings, :hard))

  def channel = @_channel ||= self.class::CoverageChannel.new(@adapter, zygote: zygote)

  def safely(id, subject, memory)
    tests = available(id)
    return [subject.verdict(:no_coverage).unreached, memory] if tests.empty?
    outcome(id, subject, tests, memory)
  rescue Kimera::Execution::Zygote::Died
    raise
  rescue Kimera::Execution::Shift::Interruption => error
    error.crashed(subject, timeout)
  rescue StandardError, ScriptError => error
    [subject.crashed(error, timeout), memory]
  end

  def outcome(id, subject, tests, memory)
    started = monotonic
    found, memory = attempt.run(id, tests, memory)
    found, memory = unmasked(id, tests, memory) if found.empty?
    [subject.judged(found, tests, monotonic - started), memory]
  end

  def unmasked(id, tests, memory)
    return [[], memory] unless @options[:confirm]
    pace = Kimera::Execution::Pace.new(@options.fetch(:timings, {}))
    self.class::Unmask.new(attempt, pace).run(id, tests, memory)
  end

  def available(id) = @coverage.fetch(id) { @coverage.fetch(id.to_s, []) }

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
