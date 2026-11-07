# frozen_string_literal: true

require "kimera/cli/run/bench"
require "kimera/cli/run/null_selection"
require "kimera/incremental/selection"
require "kimera/results/run_report"

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

class FakeExecutions
  def new(**contract) = contract
end

class FakeHarness
  attr_reader :settings, :asked, :coverage

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

  def noted(report) = report.annotate(flaky: @flakes&.to_h)
end

class FailingHarness < FakeHarness
  def initialize(failure)
    super()
    @failure = failure
  end

  def warm!(*, **) = raise(@failure)
end

class FakeSuite
  def initialize(test_ids = [], catalog: {}, files: {})
    @test_ids = test_ids
    @catalog = catalog
    @files = files
    @finished = false
  end

  attr_reader :test_ids

  def source(_files) = self

  def start = self

  def catalog(ids) = @catalog.slice(*ids)

  def describe(id) = @catalog.dig(id, "name")

  def test_file(id) = @files[id]

  def finish = (@finished = true)

  def finished? = @finished
end

class FakeSuites
  def initialize(suite = FakeSuite.new)
    @suite = suite
  end

  def load(_name) = @suite
end

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
