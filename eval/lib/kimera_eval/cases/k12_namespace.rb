# frozen_string_literal: true

module KimeraEval
  class NamespaceCase < Case
    ID = "K12"
    TITLE = "Kimera adds no top-level constant but Kimera"
    PROBE = 'before = Object.constants; require "kimera"; puts((Object.constants - before).sort)'

    def call
      added = constants
      run = differential(target(fixture("collision")), [%w[--jobs 1]]).values.first
      summary = { "top_level" => added.join(" "), "collision_run" => run["error"] ? "error" : "ok" }
      { "pass" => added == ["Kimera"] && run["error"].nil? && run["agree"] == run["mutants"], "summary" => summary }
        .merge("run" => run)
    end

    private

    def constants
      Shell.new(chdir: checkout.path).run("ruby", "-I", File.join(checkout.path, "lib"), "-e", PROBE).stdout.split
    end
  end
end
