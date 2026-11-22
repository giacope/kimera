# frozen_string_literal: true

module KimeraEval
  class RecheckCase < HoldoutCase
    ID = "H2"
    TITLE = "External holdout, batch 2: 10 projects and H1's oracle, written blind to kimera"
    HOLDOUT = File.join(ROOT, "eval", "holdout2")
    KNOWN = [
      {
        "project" => "q04_thread_local_rates", "file" => "lib/fx.rb", "line" => 23, "tool" => "killed",
        "oracle" => "survived", "mutated" => "Thread.current.fetch(:fx_cache)"
      }
    ].freeze
  end
end
