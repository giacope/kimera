# frozen_string_literal: true

require_relative "../stopwatch"

class Kimera::Execution::Shift::CoverageChannel
  class Reading
    def initialize(passed, touched, failure, took)
      @passed = passed
      @touched = touched
      @failure = failure
      @took = took
    end

    def to_h = { passed: @passed, touched: @touched, failure: @failure, took: @took }
  end

  def initialize(adapter, zygote:)
    @adapter = adapter
    @zygote = zygote
  end

  def serve(request, response)
    drain(request, response)
    emit(response, t: "done")
  end

  private

  def drain(request, response)
    while (line = request.gets)
      step(response, JSON.parse(line)["id"])
      emit(response, t: "ready")
    end
  end

  def step(response, testid)
    emit(response, t: "result", id: testid, **@zygote.call { measure(testid).to_h }.transform_keys(&:to_sym))
  end

  def measure(testid, runtime = Kimera::RUNTIME)
    ledger = Kimera::Runtime::Ledger.new
    runtime.during(nil, ledger) { reading(testid, ledger) }
  end

  def reading(testid, ledger, watch = Kimera::Execution::Stopwatch.new)
    outcome, took = watch.lap { @adapter.run([testid]) }
    Reading.new(outcome.passed?, ledger.drain!, outcome.to_h.fetch("failures")[testid], took)
  end

  def emit(io, **fields)
    io.puts(JSON.generate(fields))
  end
end
