# frozen_string_literal: true

require_relative "overrun"
require_relative "expiry"
require_relative "suspect"

Kimera::Execution::Shift::Finding =
  Data.define(:lineup, :found) do
    def id = lineup.active

    def tests = lineup.tests

    def test = tests.fetch(index)

    def index = found.fetch("index")

    def first? = index.zero?

    def onward = Kimera::Execution::Shift::Lineup.new(id, tests.drop(index + 1))

    def overran? = found.fetch("kind") == "overran"

    def expired? = found.fetch("kind") == "expired"

    def solo = Kimera::Execution::Shift::Lineup.new(id, [test])

    def calm = Kimera::Execution::Shift::Lineup.new(nil, [test])

    def control = Kimera::Execution::Shift::Lineup.new(nil, through)

    def again = Kimera::Execution::Shift::Lineup.new(id, through)

    def kill(result, killers)
      killers.remember(test)
      Kimera::Execution::Shift::Finding::Kill.new(result["failed_ids"], result["failures"])
    end

    def doubted = suspect(found.fetch("failures")[test], contradicted: false)

    def refuted(control) = suspect(control.fetch("failures")[test], contradicted: true)

    def overrun(calm, again, budget)
      Kimera::Execution::Shift::Overrun.new(test, [found.fetch("elapsed"), again["elapsed"]], calm["elapsed"], budget)
    end

    def stall(calm) = Kimera::Execution::Shift::Stall.new(test, expiry, calm.fetch("elapsed"))

    def crawl(calm)
      Kimera::Execution::Shift::Crawl.new(mutant_id: id, test: test, failure: lag(calm), contradicted: !calm["passed"])
    end

    def through = tests.first(index + 1)

    def expiry = found.fetch("failures")[test]

    def lag(calm)
      past = "ran past its soft timeout (#{calm["limit"]}s) with the mutant on"
      return "#{past} and with it off" if calm["expired"]
      return "#{past}, and failed with it off" unless calm["passed"]
      "#{past}, and took #{calm.fetch("elapsed").round(2)}s with it off"
    end

    def suspect(failure, contradicted:)
      Kimera::Execution::Shift::Suspect.new(mutant_id: id, test: test, failure: failure, contradicted: contradicted)
    end
  end

Kimera::Execution::Shift::Lineup = Data.define(:active, :tests)

Kimera::Execution::Shift::Finding::Kill =
  Data.define(:failed_ids, :failures) do
    def noted(note) = with(failures: failures.transform_values { |message| "#{note}: #{message}" })

    def conclude(&) = self

    def ruling(subject, fields)
      subject.verdict(:killed, failing_tests: failed_ids, detail: failures.values.first, **fields)
    end
  end
