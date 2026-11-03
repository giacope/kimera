# frozen_string_literal: true

module KimeraEval
  class NamespaceCase < Case
    ID = "K12"
    TITLE = "Kimera adds no top-level constant but Kimera"
    PROBE = 'before = Object.constants; require "kimera"; puts((Object.constants - before).sort)'

    def call
      added = constants
      dir = fixture("collision")
      run = differential(target(dir), [%w[--jobs 1]], oracle(dir)).values.first
      summary = { "top_level" => added.join(" "), "collision_run" => run["error"] ? "error" : "ok" }
      { "pass" => added == ["Kimera"] && run["error"].nil? && run["agree"] == run["mutants"], "summary" => summary }
        .merge("run" => run)
    end

    private

    def constants
      _, printed = Shell.new(chdir: checkout.to_s).run("ruby", "-I", File.join(checkout.to_s, "lib"), "-e", PROBE)
      printed.to_s.split
    end
  end
end
