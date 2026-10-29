# frozen_string_literal: true

require "kimera/cli/run/bench"
require "kimera/cli/run/null_selection"
require "kimera/incremental/selection"
require "kimera/results/run_report"

# The isolated tier: it judges each request with the report it holds, re-judges
# with the verdicts it holds, and writes down every request and the settings it
# was built with.
class FakeIsolation
  attr_reader :settings, :asked

  def initialize(report = Kimera::RunReport.new(results: []), rejudged: [])
    @report = report
    @rejudged = rejudged
    @asked = []
  end

  def built(settings)
    @settings = settings
    self
  end

  def verify!(ids) = @asked.push([:verify!, ids])

  def run(ids:, label:)
    @asked.push([:run, ids, label])
    @report
  end

  def rejudge(warm, label:)
    @asked.push([:rejudge, warm, label])
    @rejudged
  end
end

# Kimera::Execution::IsolatedExecution as a harness builds its isolated tier:
# what it builds is the contract it was handed.
class FakeExecutions
  def new(**contract) = contract
end

# The warm harness, and Kimera::Execution::Harness that builds it: it answers
# every run with the report it holds (or what its block answers for the ids it
# runs), and the coverage and flaky tests it was given, hands out its isolated
# tier, and writes down what it was asked, in order, and the settings it was
# built with.
class FakeHarness
  attr_reader :settings, :asked, :coverage, :flakes

  def initialize(
    report = Kimera::RunReport.new(results: []), coverage: nil, flakes: nil, isolation: FakeIsolation.new, &answer
  )
    @answer = answer || proc { report }
    @coverage = coverage
    @flakes = flakes
    @isolation = isolation
    @asked = []
  end

  def build(**settings)
    @settings = settings
    self
  end

  def warm!(files, scope: nil) = @asked.push([:warm!, files, scope])

  def without_coverage!(files) = @asked.push([:without_coverage!, files])

  def run(ids:, label:)
    @asked.push([:run, ids, label])
    @answer.call(ids)
  end

  def isolated(**settings) = @isolation.built(settings)
end

# A warm harness whose suite is not green: its warm pass raises the failure it
# holds, as the real one does when the baseline fails.
class FailingHarness < FakeHarness
  def initialize(failure)
    super()
    @failure = failure
  end

  def warm!(*, **) = raise(@failure)
end

# A suite of the tests a spec names: it lists them, names them from its
# catalog, places each in its file, and knows whether the run finished it.
class FakeSuite
  def initialize(test_ids = [], catalog: {}, files: {})
    @test_ids = test_ids
    @catalog = catalog
    @files = files
    @finished = false
  end

  attr_reader :test_ids

  def catalog(ids) = @catalog.slice(*ids)

  def describe(id) = @catalog.dig(id, "name")

  def test_file(id) = @files[id]

  def finish = (@finished = true)

  def finished? = @finished
end

# The suites of the frameworks, as Kimera::Frameworks::SUITES holds them: each
# framework loads the one suite it was given.
class FakeSuites
  def initialize(suite = FakeSuite.new)
    @suite = suite
  end

  def load(_name) = @suite
end

# What a run judges its mutants on, as Kimera::CLI::Run::Bench makes it, from
# the parts a spec hands in: the suite, the warm harness, and the lines a
# --since run finds changed (in place of git's diff). It calls its block, if
# given, as it loads the suite.
class FakeBench
  def initialize(harness: FakeHarness.new, suite: FakeSuite.new, changed: {}, &loading)
    @harness = harness
    @suite = suite
    @changed = changed
    @loading = loading || proc {}
  end

  def change(since, _root)
    since ? Kimera::Incremental::Selection.new(@changed, since) : Kimera::CLI::Run::NullSelection.new
  end

  def suite(_framework, _names) = @suite.tap { @loading.call }

  def harness(**) = @harness.build(**)
end
