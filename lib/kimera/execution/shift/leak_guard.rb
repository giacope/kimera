# frozen_string_literal: true

class Kimera::Execution::Shift::LeakGuard
  def initialize(every, &evaluator)
    @every = every
    @evaluator = evaluator
  end

  def check(io, history, index)
    return unless due?(index)
    return if history.empty?
    recheck(io, history.last)
  end

  private

  def due?(index)
    return false unless @every&.positive?
    ((index + 1) % @every).zero?
  end

  def recheck(io, id)
    return if @evaluator.call(id).killed?
    emit(io, t: "leak", id: id, detail: detail(id))
  end

  def detail(id)
    "mutant #{id} killed earlier but survived re-run (state leakage suspected)"
  end

  def emit(io, **fields)
    io.puts(JSON.generate(fields))
  end
end
