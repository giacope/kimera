# frozen_string_literal: true

module KimeraEval
  class FormalCase < Case
    ID = "K8"
    TITLE = "TLA+ model and trace checks run reproducibly"
    TRACES = "spec/property/worker_pool_spec.rb"

    def call
      steps = { "fetch" => fetch, "traces" => specs(shell.run("bundle", "exec", "ruby", "bin/spec", TRACES)) }
      steps["model_check"] = checked unless quick?
      { "pass" => steps.values.all? { |step| step["ok"] }, "summary" => steps.transform_values { |step| step["ok"] } }
        .merge("steps" => steps)
    end

    private

    def shell = Shell.new(env: { "BUNDLE_GEMFILE" => checkout.gemfile }, chdir: checkout.path, timeout: 1800)

    def fetch
      FileUtils.rm_f(File.join(checkout.path, "tmp", "tla2tools.jar"))
      result = shell.run("bundle", "exec", "ruby", "bin/model-check", "--fetch")
      { "ok" => result.ok?, "tail" => result.output.lines.last(2).join, "wall_s" => result.wall.round(1) }
    end

    def checked
      result = shell.run("bundle", "exec", "ruby", "bin/model-check")
      { "ok" => result.ok?, "wall_s" => result.wall.round(1), "tail" => result.output.lines.grep(/^==/).last(3).join }
    end
  end
end
