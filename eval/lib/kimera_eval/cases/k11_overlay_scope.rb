# frozen_string_literal: true

module KimeraEval
  # K11: two overlaid files that each assign a top-level local captured by a
  # lambda, one of which also reads __dir__ and calls require_relative at the
  # top level. Under `load` every file has its own top-level scope; an
  # overlay must behave the same, so each file's mutants run against its own
  # locals, and the oracle's verdicts hold.
  class ScopeCase < Case
    ID = "K11"
    TITLE = "Overlay files get load semantics (own top-level scope)"

    def call
      run = differential(target(fixture("overlay")), [%w[--jobs 1]]).values.first
      wrong = run.values_at("false_survived", "false_killed").compact.sum
      { "pass" => run["error"].nil? && wrong.zero? }
        .merge("summary" => { "false_verdicts" => wrong, "statuses" => run["statuses"] }, "run" => run)
    end
  end
end
