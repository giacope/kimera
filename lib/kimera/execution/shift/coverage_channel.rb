# frozen_string_literal: true

require_relative "../stopwatch"

class Kimera::Execution::Shift::CoverageChannel
  def initialize(adapter)
    @adapter = adapter
  end

  def serve(request, response)
    ledger = Kimera::Runtime.start!
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
    Kimera::Runtime.active = nil
    watch = Kimera::Execution::Stopwatch.new
    emit(response, **message(testid, ledger, watch.lap { @adapter.run([testid]) }), took: watch.last)
  end

  def message(testid, ledger, outcome)
    { t: "result", id: testid, passed: outcome.passed? }
      .merge(touched: Kimera::Runtime.drain!(ledger), failure: outcome.failures[testid])
  end

  def stop(ledger)
    Kimera::Runtime.stop!(ledger)
    Kimera::Runtime.active = nil
  end

  def emit(io, **msg)
    io.puts(JSON.generate(msg))
  end
end
