# frozen_string_literal: true

require_relative "suspect"

Kimera::Execution::Shift::Trial =
  Data.define(:adapter, :mutant, :test, :deadline) do
    def verdict(&)
      outcome = on
      return if outcome.passed?
      confirm(outcome, &)
    end

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
      Kimera::Runtime.active = active
      deadline.guard(test) { adapter.run([test]) }
    end
  end
