# frozen_string_literal: true

require_relative "lapse"

Kimera::Execution::Shift::Overrun =
  Data.define(:test, :runs, :control, :budget) do
    include Kimera::Execution::Shift::Lapse
    def detail = budget.explain(test, runs, control)
  end
