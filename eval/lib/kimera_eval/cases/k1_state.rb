# frozen_string_literal: true

module KimeraEval
  # K1: verdicts against the oracle on suites whose state outlives a test:
  # memo caches in another file, caches that hide callers from coverage,
  # globals/class variables/module ivars, an ENV flag a mutant leaks, a
  # registry and a constant later tests change, a table built at load.
  # Warm runs at --jobs 1 and 4. The two example apps are a stateless
  # control.
  class StateCase < Case
    ID = "K1"
    TITLE = "Verdicts agree with a fresh-process oracle on stateful suites"
    MODES = [%w[--jobs 1], %w[--jobs 4]].freeze
    EXAMPLES = File.join(ROOT, "examples")
    CONTROLS = {
      "sample_app" => %w[app --tests spec/**/*_spec.rb],
      "minitest_app" => %w[app --framework minitest --tests test/**/*_test.rb]
    }.freeze

    def call
      summarize(
        Dir[fixture("state", "*")].to_h { |dir| [File.basename(dir), differential(target(dir), MODES)] },
        CONTROLS.to_h { |name, args| [name, control(name, args)] }
      )
    end

    private

    def control(name, args)
      dir = File.join(EXAMPLES, name)
      runner = Oracle::Runner.new(name == "minitest_app" ? MINITEST : RSPEC, TOOLCHAIN)
      differential(target(dir, args: args), MODES, oracle(dir, runner))
    end

    def summarize(corpus, control)
      stateful = totals(corpus.values.flat_map(&:values))
      { "pass" => clean?(stateful), "summary" => headline(stateful), "stateful" => stateful.merge(by_mode(corpus)) }
        .merge("control" => totals(control.values.flat_map(&:values)), "runs" => corpus.merge(control))
    end

    def by_mode(corpus)
      MODES.to_h { |mode| ["mode #{mode.join(" ")}", totals(corpus.values.map { |runs| runs.fetch(mode.join(" ")) })] }
    end

    def clean?(stateful) = stateful.values_at("false_survived", "false_killed", "errors").sum.zero?
  end
end
