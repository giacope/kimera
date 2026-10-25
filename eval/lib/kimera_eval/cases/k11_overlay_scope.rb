# frozen_string_literal: true

module KimeraEval
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
