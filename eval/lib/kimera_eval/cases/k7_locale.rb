# frozen_string_literal: true

module KimeraEval
  # K7: kimera and its suite with LANG unset and with LANG=C. A project with
  # UTF-8 comments, strings, method names and test descriptions goes through
  # run, report, mutant and doctor; the suite's locale-sensitive specs run
  # under both locales.
  class LocaleCase < Case
    ID = "K7"
    TITLE = "Locale-independent: LANG unset and LANG=C"
    LOCALES = {
      "unset" => { "LANG" => nil, "LC_ALL" => nil, "LC_CTYPE" => nil }, "C" => { "LANG" => "C", "LC_ALL" => nil }
    }.freeze
    SPECS = %w[
      spec/integration/relative_timeout_spec.rb spec/integration/shared_state_spec.rb
      spec/kimera/cli/run/emission_spec.rb
    ].freeze
    EXPECTED = { "run" => 2, "report" => 0, "mutant" => 0, "doctor" => 0 }.freeze
    BROKEN = /Encoding|invalid byte|incompatible character/

    def call
      runs = LOCALES.to_h { |name, env| [name, commands(env).merge("suite" => suite(env))] }
      failures = runs.values.sum { |run| run.values.count { |step| !step["ok"] } }
      { "pass" => failures.zero?, "runs" => runs }.merge("summary" => tally(runs, failures))
    end

    def tally(runs, failures)
      { "failed_steps" => failures, "suite_failures" => runs.values.sum { |run| run["suite"]["failures"] } }
    end

    private

    def commands(env)
      dir = sandbox.copy(fixture("locale"))
      steps(File.join(dir, "tmp", "locale.json")).to_h do |name, arguments|
        [name, step(name, checkout.cli(*arguments, chdir: dir, env: env))]
      end
    end

    def steps(report)
      { "run" => ["run", "--report", report, "--no-progress"], "report" => ["report", report] }
        .merge("mutant" => ["mutant", "1", "--report", report], "doctor" => ["doctor"])
    end

    def step(name, result)
      text = result.output
      { "ok" => result.code == EXPECTED.fetch(name) && !text.match?(BROKEN) && intact?(name, text) }
        .merge("exit" => result.code, "tail" => text.lines.last(3).join)
    end

    def intact?(name, text) = name == "doctor" || text.include?("é")

    def suite(env)
      specs(
        Shell.new(env: { "BUNDLE_GEMFILE" => checkout.gemfile }.merge(env), chdir: checkout.path, timeout: 900)
          .run("bundle", "exec", "ruby", "bin/spec", *SPECS)
      )
    end
  end
end
