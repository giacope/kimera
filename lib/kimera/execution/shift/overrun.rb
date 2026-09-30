# frozen_string_literal: true

Kimera::Execution::Shift::Overrun =
  Data.define(:test, :runs, :control, :budget) do
    def detail = budget.explain(test, runs, control)
  end
