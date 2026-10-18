# frozen_string_literal: true

module KimeraEval
  # H2: a second external holdout, measured as H1 is. Ten projects whose
  # state leaks or hides in ways the first batch does not (prepend,
  # method_missing, refinements, Thread.current, Comparable called from C,
  # Class.new, autoload, send, before(:all), catch/throw), written blind to
  # kimera, its tests and this eval (eval/holdout2/README.md), judged by H1's
  # oracle.
  class RecheckCase < HoldoutCase
    ID = "H2"
    TITLE = "External holdout, batch 2: 10 projects and H1's oracle, written blind to kimera"
    HOLDOUT = File.join(ROOT, "eval", "holdout2")
  end
end
