# frozen_string_literal: true

module KimeraEval
  # K12: top-level constants `require "kimera"` adds, and a project that
  # defines its own top-level MutantRuntime class.
  class NamespaceCase < Case
    ID = "K12"
    TITLE = "Kimera adds no top-level constant but Kimera"

    def call
      added = constants
      run = differential(fixture("collision"), [%w[--jobs 1]]).values.first
      ok = added == ["Kimera"] && run["error"].nil? && run["agree"] == run["mutants"]
      { "pass" => ok, "summary" => { "top_level" => added.join(" "), "collision_run" => run["error"] ? "error" : "ok" } }
        .merge("run" => run)
    end

    private

    def constants
      script = 'before = Object.constants; require "kimera"; puts((Object.constants - before).sort)'
      checkout.ruby("-e", script, chdir: checkout.path).out.split
    end
  end
end
