# frozen_string_literal: true

module KimeraEval
  ROOT = File.expand_path("../..", __dir__)
  FIXTURES = File.join(ROOT, "eval", "fixtures")
  RESULTS = File.join(ROOT, "eval", "results")
end

require_relative "kimera_eval/shell"
require_relative "kimera_eval/checkout"
require_relative "kimera_eval/sandbox"
require_relative "kimera_eval/oracle"
require_relative "kimera_eval/differential"
require_relative "kimera_eval/scoreboard"
require_relative "kimera_eval/cases"
require_relative "kimera_eval/command"
