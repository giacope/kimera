# frozen_string_literal: true

Kimera::Execution::Shift::Expiry =
  Data.define(:test, :message) do
    def passed? = false

    def expired? = true

    def failed_ids = [test]

    def failures = { test => message }
  end

Kimera::Execution::Shift::Stall =
  Data.define(:test, :expiry, :control) do
    def detail = "#{expiry} with the mutant on; alone with it off, the test passed in #{control.round(2)}s"

    def noted(_note) = self
  end
