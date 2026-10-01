# frozen_string_literal: true

require_relative "../stopwatch"

class Kimera::Execution::Shift::CoverageChannel
  def initialize(adapter)
    @adapter = adapter
  end

  def serve(request, response)
    ledger = Kimera::RUNTIME.start!
    drain(request, response, ledger)
    emit(response, t: "done")
  ensure
    stop(ledger)
  end

  private

  def drain(request, response, ledger)
    while (line = request.gets)
      step(response, JSON.parse(line)["id"], ledger)
      emit(response, t: "ready")
    end
  end

  def step(response, testid, ledger)
    Kimera::RUNTIME.active = nil
    watch = Kimera::Execution::Stopwatch.new
    emit(response, **message(testid, ledger, watch.lap { @adapter.run([testid]) }), took: watch.last)
  end

  def message(testid, ledger, outcome)
    { t: "result", id: testid, passed: outcome.passed? }
      .merge(touched: ledger.drain!, failure: outcome.failures[testid])
  end

  def stop(ledger)
    Kimera::RUNTIME.stop!(ledger)
    Kimera::RUNTIME.active = nil
  end

  def emit(io, **fields)
    io.puts(JSON.generate(fields))
  end
end
