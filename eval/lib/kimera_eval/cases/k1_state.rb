# frozen_string_literal: true

module KimeraEval
  # K1: verdicts against the oracle on suites whose state outlives a test:
  # memo caches in another file, caches that hide callers from coverage,
  # globals/class variables/module ivars, an ENV flag a mutant leaks, a
  # registry and a constant later tests change. Warm runs at --jobs 1 and 4.
  # The two example apps are a stateless control.
  class StateCase < Case
    ID = "K1"
    TITLE = "Verdicts agree with a fresh-process oracle on stateful suites"
    MODES = [%w[--jobs 1], %w[--jobs 4]].freeze

    def call
      corpus = Dir[fixture("state", "*")].sort.to_h { |dir| [File.basename(dir), differential(dir, MODES)] }
      control = controls.to_h { |name, dir, args| [name, differential(dir, MODES, args: args)] }
      summarize(corpus, control)
    end

    private

    def controls
      examples = File.join(ROOT, "examples")
      [["sample_app", File.join(examples, "sample_app"), ["app", "--tests", "spec/**/*_spec.rb"]],
       ["minitest_app", File.join(examples, "minitest_app"),
        ["app", "--framework", "minitest", "--tests", "test/**/*_test.rb"]]]
    end

    def oracle_command(dir)
      return super unless File.basename(dir) == "minitest_app"
      ["bundle", "exec", "ruby", "-Itest", "-e", "Dir.glob('test/**/*_test.rb').sort.each { |f| require File.expand_path(f) }"]
    end

    def framework(dir)
      return "rspec" unless File.exist?(File.join(dir, ".kimera.yml"))
      super
    end

    def summarize(corpus, control)
      stateful = totals(corpus.values.flat_map(&:values))
      { "pass" => clean?(stateful), "summary" => headline(stateful), "stateful" => stateful.merge(by_mode(corpus)), "control" => totals(control.values.flat_map(&:values)) }
        .merge("runs" => corpus.merge(control))
    end

    def by_mode(corpus)
      MODES.to_h { |mode| ["mode #{mode.join(" ")}", totals(corpus.values.map { |runs| runs.fetch(mode.join(" ")) })] }
    end

    def headline(stateful)
      judged = stateful["mutants"] - stateful["abstained"] - stateful["unbakeable"]
      stateful.slice("mutants", "false_survived", "false_killed", "abstained")
        .merge("agreement_pct" => judged.zero? ? nil : (100.0 * stateful["agree"] / judged).round(1))
    end

    def clean?(stateful) = stateful.values_at("false_survived", "false_killed", "abstained", "errors").sum.zero?
  end
end
