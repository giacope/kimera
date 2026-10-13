# frozen_string_literal: true

module KimeraEval
  # K8: the TLA+ checks from a clean checkout: the pinned tla2tools.jar
  # downloads and verifies, the worker pool's traces validate against the
  # model, and (unless --quick) the model checks CI runs pass.
  class ModelCheckCase < Case
    ID = "K8"
    TITLE = "TLA+ model and trace checks run reproducibly"

    def call
      fetched = fresh_fetch
      traces = spec("spec/property/worker_pool_spec.rb")
      checks = context.quick? ? nil : model_check
      steps = { "fetch" => fetched, "traces" => traces, "model_check" => checks }.compact
      { "pass" => steps.values.all? { |step| step["ok"] }, "summary" => steps.transform_values { |step| step["ok"] } }
        .merge("steps" => steps)
    end

    private

    def shell = Shell.new(env: { "BUNDLE_GEMFILE" => checkout.gemfile }, chdir: checkout.path, timeout: 1800)

    def fresh_fetch
      FileUtils.rm_f(File.join(checkout.path, "tmp", "tla2tools.jar"))
      result = shell.run("bundle", "exec", "ruby", "bin/model-check", "--fetch")
      { "ok" => result.ok?, "tail" => result.output.lines.last(2).join, "wall_s" => result.wall.round(1) }
    end

    def spec(path)
      result = shell.run("bundle", "exec", "ruby", "bin/spec", path)
      examples, failures = result.out.scan(/(\d+) examples?, (\d+) failures?/).last
      { "ok" => result.ok?, "examples" => examples.to_i, "failures" => failures.to_i, "wall_s" => result.wall.round(1) }
    end

    def model_check
      result = shell.run("bundle", "exec", "ruby", "bin/model-check")
      { "ok" => result.ok?, "wall_s" => result.wall.round(1), "tail" => result.output.lines.grep(/^==/).last(3).join }
    end
  end
end
