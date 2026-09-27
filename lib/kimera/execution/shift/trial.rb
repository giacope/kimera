# frozen_string_literal: true

require_relative "suspect"

Kimera::Execution::Shift::Trial =
  Data.define(:adapter, :mutant, :test) do
    def verdict(deadline, &)
      outcome = on
      return if outcome.passed?
      deadline.check!(test)
      confirm(outcome, deadline, &)
    end

    def confirm(outcome, deadline, &)
      control = off
      again = on if control.passed?
      deadline.check!(test)
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
      adapter.run([test])
    end
  end
