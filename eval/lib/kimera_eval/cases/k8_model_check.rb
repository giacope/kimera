# frozen_string_literal: true

module KimeraEval
  class FormalCase < Case
    ID = "K8"
    TITLE = "TLA+ model and trace checks run reproducibly"
    TRACES = "spec/property/worker_pool_spec.rb"

    def call
      steps = { "fetch" => fetch, "traces" => specs(*shell.run("bundle", "exec", "ruby", "bin/spec", TRACES)) }
      steps["model_check"] = checked unless quick?
      { "pass" => steps.values.all? { |step| step["ok"] }, "summary" => steps.transform_values { |step| step["ok"] } }
        .merge("steps" => steps)
    end

    private

    def shell = checkout.shell(timeout: 1800)

    def fetch
      exit, printed, usage = refetch
      { "ok" => exit.ok?, "tail" => printed.output.lines.last(2).join }.merge(usage.timed(1))
    end

    def refetch
      FileUtils.rm_f(File.join(checkout.to_s, "tmp", "tla2tools.jar"))
      shell.run("bundle", "exec", "ruby", "bin/model-check", "--fetch")
    end

    def checked
      exit, printed, usage = shell.run("bundle", "exec", "ruby", "bin/model-check")
      { "ok" => exit.ok? }.merge(usage.timed(1)).merge("tail" => printed.output.lines.grep(/^==/).last(3).join)
    end
  end
end
