# frozen_string_literal: true

require_relative "suspect"

Kimera::Execution::Shift::Finding =
  Data.define(:tests, :found) do
    def test = tests.fetch(index)

    def index = found.fetch("index")

    def through = tests.first(index + 1)

    def rest = tests.drop(index + 1)

    def overran? = found.fetch("kind") == "overran"

    def elapsed = found.fetch("elapsed")

    def doubted(id) = suspect(id, found.fetch("failures")[test], contradicted: false)

    def refuted(id, control) = suspect(id, control.fetch("failures")[test], contradicted: true)

    def suspect(id, failure, contradicted:)
      Kimera::Execution::Shift::Suspect.new(mutant_id: id, test: test, failure: failure, contradicted: contradicted)
    end
  end

Kimera::Execution::Shift::Finding::Kill = Data.define(:failed_ids, :failures)
