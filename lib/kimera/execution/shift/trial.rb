# frozen_string_literal: true

require_relative "overrun"
require_relative "suspect"

Kimera::Execution::Shift::Trial =
  Data.define(:adapter, :mutant, :test, :deadline) do
    def verdict(&)
      outcome = on
      return confirm(outcome, &) unless outcome.passed?
      lagged if deadline.overran?(test)
    end

    def lagged
      first = deadline.elapsed
      return unless calm?
      control = deadline.elapsed
      on
      overrun([first, deadline.elapsed], control) if deadline.overran?(test)
    end

    def overrun(runs, control) = Kimera::Execution::Shift::Overrun.new(test, runs, control, deadline.budget)

    def calm? = off.passed? && !deadline.overran?(test)

    def confirm(outcome, &)
      control = off
      again = on if control.passed?
      return suspect(control) unless again && !again.passed?
      outcome.tap(&)
    end

    def suspect(control)
      Kimera::Execution::Shift::Suspect.new(mutant, test, control.failures[test], !control.passed?)
    end

    def on = run(mutant)

    def off = run(nil)

    def run(active)
      Kimera::RUNTIME.active = active
      deadline.guard(test) { adapter.run([test]) }
    end
  end
