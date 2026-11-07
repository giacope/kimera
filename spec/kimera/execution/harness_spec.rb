# frozen_string_literal: true

require "fileutils"
require "json"
require "kimera/execution/harness"
require "kimera/execution/test_filter"
require "kimera/frameworks/suite"
require "kimera/registry/builder"
require "tmpdir"

using ResultFields
using PointFields

RSpec::Matchers.define_negated_matcher(:not_output, :output)

RSpec.describe(Kimera::Execution::Harness) do
  let(:registry) do
    Kimera::RegistryScan.new.source(<<~RUBY, file: "calc.rb")
      def a(x, y)
        x > y
      end
    RUBY
  end
  let(:ids) { registry.each.map { |m, _p| m.to_i } }

  def adapter(coverage: {}, failing: [], message: nil)
    Class.new(Kimera::Frameworks::Suite) do
      define_method(:initialize) do
        @coverage = coverage
        @failing = failing
      end
      def source(_files) = self
      def test_ids = @coverage.keys
      define_method(:run) do |test_ids|
        test_ids.each { |t| Array(@coverage[t]).each { |mid| Kimera::RUNTIME.active?(mid) } }
        failed = test_ids & @failing
        Kimera::Frameworks::RunOutcome.new(
          passed: failed.empty?, failed_ids: failed,
          failures: failed.to_h { |t| [t, message || "assertion failed in #{t}"] }
        )
      end
    end.new
  end

  def harness(adapter, **)
    described_class.build(registry: registry, adapter: adapter, **)
  end

  def reloader(
    adapter, catalog: registry, isolation: Kimera::Execution::Isolation.new, root: ".", aliases: nil
  )
    workspace = Kimera::Execution::Reload::Workspace.new(root: root, aliases: aliases)
    Kimera::Execution::Reload.new(registry: catalog, adapter: adapter, isolation: isolation, workspace: workspace)
  end

  def reselected(outer, coverage, failing, test_ids)
    Kimera::RUNTIME.active = outer
    test_ids.each { |t| Array(coverage[t]).each { |mid| Kimera::RUNTIME.active?(mid) } }
    failed = test_ids & failing
    Kimera::Frameworks::RunOutcome.new(passed: failed.empty?, failed_ids: failed)
  end

  def reselecting(coverage: {}, failing: [])
    run = method(:reselected).curry[Kimera::RUNTIME.active, coverage, failing]
    Class.new(Kimera::Frameworks::Suite) do
      def source(_files) = self
      define_method(:test_ids) { coverage.keys }
      define_method(:run) { |test_ids| run.call(test_ids) }
    end.new
  end

  def processes(pids)
    Class.new(Kimera::Frameworks::Suite) do
      def source(_files) = self
      def test_ids = ["t1"]
      define_method(:run) do |_ids|
        pids << Process.pid
        Kimera::Frameworks::RunOutcome.new(passed: true, failed_ids: [])
      end
    end.new
  end

  def reselection
    outer = Kimera::RUNTIME.active
    Class.new(Kimera::Execution::Isolation) do
      define_method(:around) do |&block|
        Kimera::RUNTIME.active = outer
        block.call
      end
    end.new
  end

  def responder(status:, extra: nil)
    leaks = ->(id) { extra ? [JSON.generate(t: "leak", id: id, detail: extra)] : [] }
    lambda do |_slot|
      forked do |request, response|
        serving(request, response) { |id| judged(response, id, status, *leaks.call(id)) }
        exit!(0)
      end
    end
  end

  def aliasing(name, parent)
    subclass =
      Class.new(parent) do
        alias_method :remembered, :memo
        define_method(:memo) { |a, b| remembered(a, b) }
      end
    stub_const(name, subclass)
  end

  def journal = ProgressJournal.new

  def triage(registry) = Kimera::Execution::Triage.new(Kimera::Execution::Verdicts.new(registry))

  it "answers unmeasured coverage until its warm pass measures it" do
    expect(harness(adapter(coverage: { "t1" => [], "t2" => [] })).survey.coverage.fetch(ids.first)).to(eq(%w[t1 t2]))
  end

  describe "hard_timeout default" do
    it "derives from soft_timeout when not given" do
      h = harness(adapter, soft_timeout: 5.0)
      expect(h.__send__(:hard)).to(eq((5.0 * 3) + 1))
    end

    it "falls back to 30s when soft_timeout is nil" do
      h = harness(adapter, soft_timeout: nil)
      expect(h.__send__(:hard)).to(eq(30.0))
    end

    it "clamps jobs to at least 1", :aggregate_failures do
      expect(harness(adapter, jobs: 0).__send__(:jobs)).to(eq(1))
      expect(harness(adapter, jobs: 4).__send__(:jobs)).to(eq(4))
    end
  end

  describe "#measure!" do
    it "builds a mutant => covering-tests map from the touch-log", :aggregate_failures do
      h = harness(adapter(coverage: { "t1" => [ids.first], "t2" => ids }))
      h.__send__(:measure!)
      expect(h.survey.coverage[ids.first]).to(contain_exactly("t1", "t2"))
      expect(h.survey.coverage[ids.last]).to(contain_exactly("t2"))
    end

    it "raises BaselineFailure listing failing tests that cover an in-scope mutant" do
      h = harness(adapter(coverage: { "t1" => [], "t2" => [ids.first] }, failing: ["t2"]))
      expect { h.__send__(:measure!) }.to(raise_error(Kimera::Execution::BaselineFailure, /t2/))
    end

    it "names the worker that ran each failing test when the parallel baseline is red" do
      h = described_class.build(
        registry: registry, jobs: 2,
        adapter: adapter(coverage: { "t1" => [], "t2" => [ids.first] }, failing: ["t2"])
      )
      expect { h.__send__(:measure!) }
        .to(raise_error(Kimera::Execution::BaselineFailure, /per worker.*\n    worker \d: ran \d; failed #\d t2/m))
    end

    it "includes the failing assertion message in the BaselineFailure" do
      h = harness(adapter(coverage: { "t2" => [ids.first] }, failing: ["t2"]))
      expect { h.__send__(:measure!) }.to(raise_error(Kimera::Execution::BaselineFailure, /assertion failed in t2/))
    end

    it "tells you how to reproduce the failure without kimera" do
      h = harness(adapter(coverage: { "t2" => [ids.first] }, failing: ["t2"]))
      expect { h.__send__(:measure!) }.to(raise_error(Kimera::Execution::BaselineFailure, /rspec t2 --order defined/))
    end

    def reproducing(asked)
      adapter(coverage: { "t2" => [ids.first] }, failing: ["t2"]).tap do |fake|
        fake.define_singleton_method(:[]) do |*shown|
          Class.new(Kimera::Frameworks::BareSelection) { define_method(:to_s) { (asked << shown) && "ruby -n t2" } }
            .new(shown, self)
        end
      end
    end

    it "asks the adapter for its framework's reproduce command, first ids only", :aggregate_failures do
      asked = []
      fake = reproducing(asked)
      expect { harness(fake).__send__(:measure!) }
        .to(raise_error(Kimera::Execution::BaselineFailure, /reproduce without kimera: ruby -n t2\z/))
      expect(asked).to(eq([["t2"]]))
    end

    it "names the failing tests on the summary line" do
      h = harness(adapter(coverage: { "t2" => [ids.first] }, failing: ["t2"]))
      expect { h.__send__(:measure!) }
        .to(raise_error(Kimera::Execution::BaselineFailure, /baseline suite is not green: t2/))
    end

    def failure(harness)
      harness.__send__(:measure!)
      raise(RuntimeError, "expected BaselineFailure")
    rescue Kimera::Execution::BaselineFailure => error
      error
    end

    it "truncates an assertion message past the limit", :aggregate_failures do
      long = "m" * (Kimera::Execution::BaselineFailure::Summary::MAX_MESSAGE + 50)
      h = harness(adapter(coverage: { "t2" => [ids.first] }, failing: ["t2"], message: long))
      error = failure(h)
      expect(error.message).to(include("#{"m" * Kimera::Execution::BaselineFailure::Summary::MAX_MESSAGE}…"))
      expect(error.message).not_to(include("m" * (Kimera::Execution::BaselineFailure::Summary::MAX_MESSAGE + 1)))
    end

    it "leaves an assertion message exactly at the limit untouched", :aggregate_failures do
      exact = "n" * Kimera::Execution::BaselineFailure::Summary::MAX_MESSAGE
      h = harness(adapter(coverage: { "t2" => [ids.first] }, failing: ["t2"], message: exact))
      error = failure(h)
      expect(error.message).to(include(exact))
      expect(error.message).not_to(include("…"))
    end

    it "excludes a failing test that covers no in-scope mutant from the baseline", :aggregate_failures do
      h = harness(adapter(coverage: { "t1" => [ids.first], "t2" => [] }, failing: ["t2"]))
      measured = nil
      expect { measured = h.__send__(:measure!) }.not_to(raise_error)
      expect { noticed(h, measured) }.to(output(/1 test\(s\) fail in the baseline.*excluded/).to_stderr)
      expect(h.survey.coverage[ids.first]).to(include("t1"))
    end

    def noticed(harness, measured) = harness.__send__(:notice, measured.screened(harness.__send__(:screen)), measured)

    def crowded
      failing = %w[t2 t3 t4 t5 t6 t7 t8]
      coverage = failing.to_h { |id| [id, []] }.merge("t1" => [ids.first])
      h = harness(adapter(coverage: coverage, failing: failing, message: "boom\nframe"))
      [h, h.__send__(:measure!)]
    end

    it "names each excluded failing test with its failure" do
      expect { noticed(*crowded) }.to(output(/coverage is unknown.*:\n  t2: boom\n/).to_stderr)
    end

    it "names failing tests up to a limit, then counts the rest and gives their plain run" do
      expect { noticed(*crowded) }.to(output(/\n  t6: boom\n  … and 2 more\n  plain run: rspec t2 /).to_stderr)
    end

    it "closes its own ledger afterward" do
      h = harness(adapter(coverage: { "t1" => [ids.first] }))
      expect { h.__send__(:measure!) }.not_to(change { Array(Kimera::RUNTIME.instance_variable_get(:@ledgers)).size })
    end

    def resetting
      Class.new(Kimera::Frameworks::Suite) do
        def source(_files) = self
        def test_ids = %w[t_reset t_after]
        define_method(:run) do |test_ids|
          test_ids.each do |t|
            if t == "t_reset"
              Kimera::RUNTIME.active?(42)
              Kimera::RUNTIME.reset!
            end
            Kimera::RUNTIME.active?(99) if t == "t_after"
          end
          Kimera::Frameworks::RunOutcome.new(passed: true, failed_ids: [])
        end
      end.new
    end

    it "keeps coverage recorded by an example that resets the runtime", :aggregate_failures do
      h = harness(resetting)
      h.__send__(:measure!)
      expect(h.survey.coverage[42]).to(contain_exactly("t_reset"))
      expect(h.survey.coverage[99]).to(contain_exactly("t_after"))
    end

    def nested
      Class.new(Kimera::Frameworks::Suite) do
        def source(_files) = self
        def test_ids = ["t_nested"]
        define_method(:run) do |_ids|
          inner = Kimera::RUNTIME.start!
          Kimera::RUNTIME.active?(7)
          inner.drain!
          Kimera::RUNTIME.stop!(inner)
          Kimera::Frameworks::RunOutcome.new(passed: true, failed_ids: [])
        end
      end.new
    end

    it "keeps coverage for an example that runs its own nested measurement" do
      h = harness(nested)
      h.__send__(:measure!)
      expect(h.survey.coverage[7]).to(contain_exactly("t_nested"))
    end

    it "keeps the loop's bookkeeping observable when the suite re-selects a mutant", :aggregate_failures do
      progress = journal
      h = harness(reselecting(coverage: { "t1" => [ids.first], "t2" => [] }), progress: progress)
      expect { h.__send__(:measure!) }.not_to(change { Array(Kimera::RUNTIME.instance_variable_get(:@ledgers)).size })
      expect(h.survey.coverage[ids.first]).to(eq(["t1"]))
      expect(progress.events).to(eq([[:start, 2, "baseline"], [:tick, nil], [:tick, nil], [:finish]]))
    end

    it "still gates on a failing example when the suite re-selects a mutant" do
      h = harness(reselecting(coverage: { "t1" => [ids.first] }, failing: ["t1"]))
      expect { h.__send__(:measure!) }.to(raise_error(Kimera::Execution::BaselineFailure, /t1/))
    end

    def ticker
      Class.new do
        def during(_total, _label = nil)
          yield(
            lambda do |_status = nil|
              Kimera::RUNTIME.active?(9_999_991)
              :ticked
            end
          )
        end
      end.new
    end

    it "discards touches recorded between examples" do
      h = harness(adapter(coverage: { "t1" => [], "t2" => [] }), progress: ticker)
      h.__send__(:measure!)
      expect(h.survey.coverage).not_to(have_key(9_999_991))
    end

    it "runs no baseline test in this process, even at jobs == 1" do
      pids = []
      h = harness(processes(pids))
      h.__send__(:measure!)
      expect(pids).to(be_empty)
    end

    it "fans the baseline out to forked workers at jobs > 1" do
      pids = []
      h = described_class.build(registry: registry, adapter: processes(pids), jobs: 2)
      h.__send__(:measure!)
      expect(pids).to(be_empty)
    end

    def empty
      progress = journal
      h = harness(adapter(coverage: {}), progress: progress)
      before = Array(Kimera::RUNTIME.instance_variable_get(:@ledgers)).size

      expect { h.__send__(:measure!) }.not_to(raise_error)
      [before, Array(Kimera::RUNTIME.instance_variable_get(:@ledgers)).size, h.survey.coverage, progress.events]
    end

    it "passes trivially on an empty suite: no raise, no coverage, balanced ledger", :aggregate_failures do
      before, after, coverage, events = empty
      expect(after).to(eq(before))
      expect(coverage).to(eq({}))
      expect(events).to(eq([[:start, 0, "baseline"], [:finish]]))
    end
  end

  describe "BaselinePass#bank" do
    let(:pass) do
      Kimera::Execution::BaselinePass.new(adapter: adapter, registry: registry)
    end

    def banked(test_id, touched)
      pass.__send__(:bank, test_id, touched)
      pass.__send__(:tally)
    end

    it "banks a failing test that covers an in-scope mutant as a failure", :aggregate_failures do
      tally = banked("t1", [ids.first])
      expect(tally.to_h.fetch(:failures)).to(eq(["t1"]))
      expect(tally.to_h.fetch(:irrelevant)).to(be_empty)
    end

    it "routes a failing test touching no in-scope mutant to irrelevant", :aggregate_failures do
      tally = banked("t2", [])
      expect(tally.to_h.fetch(:failures)).to(be_empty)
      expect(tally.to_h.fetch(:irrelevant)).to(eq(["t2"]))
    end

    it "charges a lost parallel test and advances progress", :aggregate_failures do
      ticks = []
      lost = Kimera::Execution::BaselinePass.new(adapter: adapter, registry: registry)
      lost.__send__(:lost, ->(status = nil) { ticks << status }, "t2", :crash)

      expect(lost.__send__(:tally).to_h.fetch(:failures)).to(eq(["t2"]))
      expect(ticks).to(eq([nil]))
    end

    def lost_messages
      lost = Kimera::Execution::BaselinePass.new(adapter: adapter, registry: registry)
      tick = Kimera::Execution::NullProgress::UNSEEN
      lost.__send__(:lost, tick, "t1", :timeout, nil)
      lost.__send__(:relapse, tick, "t1", :timeout)
      lost.__send__(:lost, tick, "t2", :crash, nil)
      lost.__send__(:tally).to_h.fetch(:messages)
    end

    it "explains a test whose worker hit the hard timeout twice" do
      expect(lost_messages["t1"]).to(
        eq(
          "its worker was killed at the hard timeout (--hard-timeout) before reporting a result, " \
            "and again when rerun alone"
        )
      )
    end

    it "explains a test whose worker died" do
      expect(lost_messages["t2"]).to(eq("its worker died before reporting a result"))
    end
  end

  describe "#measure! parallel path (jobs > 1)" do
    def measurement(coverage)
      h = described_class.build(registry: registry, adapter: adapter(coverage: coverage), jobs: 2)
      h.__send__(:measure!)
      h.survey.coverage
    end

    it "fans the coverage pass across the pool and matches the serial map", :aggregate_failures do
      coverage = measurement({ "t1" => [ids.first], "t2" => ids })
      expect(coverage[ids.first]).to(contain_exactly("t1", "t2"))
      expect(coverage[ids.last]).to(contain_exactly("t2"))
    end

    it "raises BaselineFailure when a forked example fails" do
      h = described_class.build(
        registry: registry, jobs: 2,
        adapter: adapter(coverage: { "t1" => [], "t2" => [ids.first] }, failing: ["t2"])
      )
      expect { h.__send__(:measure!) }.to(raise_error(Kimera::Execution::BaselineFailure, /t2/))
    end

    it "names the worker that ran each failing test when the parallel baseline is red" do
      h = described_class.build(
        registry: registry, jobs: 2,
        adapter: adapter(coverage: { "t1" => [], "t2" => [ids.first] }, failing: ["t2"])
      )
      expect { h.__send__(:measure!) }
        .to(raise_error(Kimera::Execution::BaselineFailure, /per worker.*\n    worker \d: ran \d; failed #\d t2/m))
    end
  end

  describe "baseline progress and quieting" do
    it "starts a baseline phase, ticks per example, and clears the line" do
      progress = journal
      h = harness(adapter(coverage: { "t1" => [], "t2" => [] }), progress: progress)
      h.__send__(:measure!)

      expect(progress.events).to(eq([[:start, 2, "baseline"], [:tick, nil], [:tick, nil], [:finish]]))
    end

    it "clears the progress line even when the baseline fails", :aggregate_failures do
      progress = journal
      h = harness(adapter(coverage: { "t1" => [ids.first] }, failing: ["t1"]), progress: progress)
      expect { h.__send__(:measure!) }.to(raise_error(Kimera::Execution::BaselineFailure))
      expect(progress.events.last).to(eq([:finish]))
    end

    def noisy
      Class.new(Kimera::Frameworks::Suite) do
        def source(_files) = self
        def test_ids = ["t1"]
        define_method(:run) do |_ids|
          $stdout.puts("SUITE NOISE out")

          warn "SUITE NOISE err"
          Kimera::Frameworks::RunOutcome.new(passed: true, failed_ids: [])
        end
      end.new
    end

    it "swallows suite writes to stdout/stderr during the serial baseline" do
      h = harness(noisy)
      expect { h.__send__(:measure!) }.to(not_output.to_stdout.and(not_output.to_stderr))
    end
  end

  describe "parallel coverage progress (jobs > 1)" do
    def parallel
      progress = journal
      described_class.build(
        registry: registry, jobs: 2, progress: progress,
        adapter: adapter(coverage: { "t1" => [], "t2" => [] })
      ).__send__(:measure!)
      progress
    end

    it "starts a baseline phase, ticks per example, and clears the line", :aggregate_failures do
      progress = parallel
      expect(progress.events.first).to(eq([:start, 2, "baseline"]))
      expect(progress.events.count { |e| e == [:tick, nil] }).to(eq(2))
      expect(progress.events.last).to(eq([:finish]))
    end
  end

  describe "class-body (isolated-only) routing" do
    def body
      registry =
        Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: ["rails_validation"]))
          .source("class M\n  validates :email\nend\n", file: "m.rb")
      progress = journal
      [
        described_class.build(registry: registry, adapter: adapter, progress: progress)
          .run(ids: [registry.each.first.first.to_i]),
        progress
      ]
    end

    it "reports class-body mutants as :isolated_only without evaluating them", :aggregate_failures do
      report, progress = body
      result = report.to_a.first
      expect(result.status).to(eq(:isolated_only))
      expect(result.detail).to(eq(Kimera::Reason::CLASS_BODY_REASON))
      expect(progress.events).to(include(%i[tick isolated_only]))
    end

    it "neither gates nor drags the score", :aggregate_failures do
      report, = body
      expect(report.select { it.status?(:survived) }).to(be_empty)
      expect(report.score.to_f).to(eq(1.0))
      expect(report.score.to_s).to(include("isolated_only=1"))
    end
  end

  describe "load-time (isolated-only) routing" do
    let(:dir) { Dir.mktmpdir }

    after { FileUtils.remove_entry(dir) }

    def loading(path)
      Class.new(Kimera::Frameworks::Suite) do
        define_method(:source) { |_files| load(path) && HarnessMacro.charges(true) && self }
        def test_ids = ["t1"]
        def run(_ids) = Kimera::Frameworks::RunOutcome.new(passed: true, failed_ids: [])
      end.new
    end

    def warmed
      path = File.join(dir, "harness_macro.rb")
      File.write(path, "module HarnessMacro\n  def self.charges(flag)\n    flag ? 1 : 2\n  end\nend\n")
      registry = Kimera::RegistryScan.new(root: dir).build([path])
      h = described_class.build(registry: registry, adapter: loading(path), source_root: dir, leak_every: 0)
      h.warm!(["t1"])
      h.run.to_a
    end

    it "reports the mutants of a method the suite ran while loading as isolated-only", :aggregate_failures do
      stub_const("HarnessMacro", Module.new)
      results = warmed
      expect(results.map(&:status).uniq).to(eq([:isolated_only]))
      expect(results.first.detail).to(eq(Kimera::Reason::LOAD_REASON))
    end
  end

  describe "#load!" do
    def rails_with(app) = stub_const("Rails", Data.define(:application).new(app))

    it "eager-loads a detected Rails application before overlaying" do
      app = FakeApplication.new
      rails_with(app) && harness(adapter).__send__(:load!)
      expect(app.eager_loads).to(eq(1))
    end

    it "warns but continues when eager loading fails" do
      rails_with(FakeApplication.new(RuntimeError.new("boom")))
      expect { harness(adapter).__send__(:load!) }.to(output(/eager_load! failed \(RuntimeError: boom\)/).to_stderr)
    end

    it "is a no-op outside Rails" do
      expect { harness(adapter).__send__(:load!) }.not_to(output.to_stderr)
    end

    it "skips an application that cannot eager-load, without warning" do
      rails_with(Object.new)
      expect { harness(adapter).__send__(:load!) }.not_to(output.to_stderr)
    end
  end

  describe "relative time budget" do
    def dawdling(target)
      Class.new(Kimera::Frameworks::Suite) do
        def test_ids = %w[t1]
        define_method(:run) do |_test_ids|
          sleep(0.3) if Kimera::RUNTIME.active?(target)
          Kimera::Frameworks::RunOutcome.new(passed: true, failed_ids: [])
        end
      end.new
    end

    def judged(**)
      target = ids.first
      h = harness(dawdling(target), timeout_factor: 2.0, timeout_slack: 0.1, **)
      h.__send__(:measure!)
      h.run(ids: [target]).to_a.first
    end

    it "times each baseline test and holds each covering test to its budget", :aggregate_failures do
      result = judged
      expect(result.status).to(eq(:timeout))
      expect(result.detail).to(match(/\At1 ran past its relative time budget .*× 2\.0 \+ 0\.1s\), and in /))
    end

    it "times the baseline tests of a parallel coverage pass too" do
      expect(judged(jobs: 2).status).to(eq(:timeout))
    end

    it "is off under relative_timeout: false" do
      expect(judged(relative_timeout: false).status).to(eq(:survived))
    end

    it "falls back to the default slack" do
      expect(judged(timeout_slack: nil).status).to(eq(:survived))
    end
  end

  describe "#warm! wiring" do
    include_context("with an inline zygote")

    let(:dir) { Dir.mktmpdir }

    after { FileUtils.remove_entry(dir) }

    def catalog(name)
      File.write(File.join(dir, "#{name}.rb"), <<~RUBY)
        class #{name.capitalize}
          def gt(a, b)
            a > b
          end
        end
      RUBY
      Kimera::RegistryScan.new(root: dir).build([File.join(dir, "#{name}.rb")])
    end

    def sink(sink)
      Class.new(Kimera::Frameworks::Suite) do
        define_method(:initialize) { |s| @sink = s }
        define_method(:source) do |files|
          @sink.concat(Array(files))
          self
        end
        def test_ids = ["t1"]
        def run(_ids) = Kimera::Frameworks::RunOutcome.new(passed: true, failed_ids: [])
      end.new(sink)
    end

    def files(name)
      seen = []
      inline(registry: catalog(name), adapter: sink(seen), source_root: dir).without_coverage!(["spec/a_spec.rb"])
      seen
    end

    it "hands the test files to the adapter" do
      stub_const("Warmwire", Class.new)
      expect(files("warmwire")).to(eq(["spec/a_spec.rb"]))
    end

    def red
      Class.new(Kimera::Frameworks::Suite) do
        def source(_files) = self
        def test_ids = ["t1"]
        def run(_ids) = Kimera::Frameworks::RunOutcome.new(passed: false, failed_ids: ["t1"])
      end.new
    end

    it "raises BaselineFailure from the coverage-off baseline check too" do
      stub_const("Warmred", Class.new)
      registry = catalog("warmred")
      h = inline(registry: registry, adapter: red, source_root: dir)
      expect { h.without_coverage!(["t1"]) }.to(raise_error(Kimera::Execution::BaselineFailure, /t1/))
    end

    def green(mods = nil)
      Class.new(Kimera::Frameworks::Suite) do
        def source(_files) = self
        def test_ids = ["t1"]
        def run(_ids) = Kimera::Frameworks::RunOutcome.new(passed: true, failed_ids: [])
        class_exec(&mods) if mods
      end.new
    end

    def starts
      proc do
        attr_reader(:booted)

        def hooks = self

        def start = @booted = true
      end
    end

    it "fires the adapter's suite-level setup hook during warm-up" do
      stub_const("Warmsuite", Class.new)
      registry = catalog("warmsuite")
      ad = green(starts)
      inline(registry: registry, adapter: ad, source_root: dir).without_coverage!(["t1"])
      expect(ad.booted).to(be(true))
    end

    def active(id)
      Class.new(Kimera::Frameworks::Suite) do
        define_method(:initialize) { |mid| @id = mid }
        def source(_files) = self
        def test_ids = ["t1"]
        define_method(:run) do |test_ids|
          Kimera::RUNTIME.active?(@id) if test_ids.any?
          Kimera::Frameworks::RunOutcome.new(passed: true, failed_ids: [])
        end
      end.new(id)
    end

    def default(name)
      registry = catalog(name)
      mid = registry.each.map { |m, _p| m.to_i }.first
      h = inline(registry: registry, adapter: active(mid), source_root: dir)
      h.warm!(["t1"])
      [mid, h.survey.coverage]
    end

    it "measures coverage by default when no flag is given" do
      stub_const("Warmdefault", Class.new)
      mid, coverage = default("warmdefault")
      expect(coverage[mid]).to(eq(["t1"]))
    end

    def rails = FakeApplication.new.tap { |app| stub_const("Rails", Data.define(:application).new(app)) }

    it "eager-loads a detected Rails app during warm-up" do
      stub_const("Warmeager", Class.new)
      registry = catalog("warmeager")
      app = rails
      inline(registry: registry, adapter: green, source_root: dir).without_coverage!(["t1"])
      expect(app.eager_loads).to(eq(1))
    end

    def database(name)
      FakeRails.unconnected(self)
      inline(registry: catalog(name), adapter: green, source_root: dir, isolate_db: true)
    end

    it "wires DB isolation during warm-up when isolate_db is on" do
      stub_const("Warmiso", Class.new)
      h = database("warmiso")
      h.without_coverage!(["t1"])
      expect(h.__send__(:isolation)).to(be_a(Kimera::Execution::CompositeIsolation))
    end

    def first(registry) = registry.each.map { |m, _p| m.to_i }.first

    def ungated(name)
      registry = catalog(name)
      inline(
        registry: registry, source_root: dir,
        adapter: adapter(coverage: { "t1" => [first(registry)], "t2" => [] }, failing: ["t2"])
      )
    end

    it "reports failing tests that gate nothing, after warm-up" do
      stub_const("Warmirr", Class.new)
      h = ungated("warmirr")
      expect { h.warm!(%w[t1 t2]) }.to(output(/1 test\(s\) fail in the baseline, in a plain run too/).to_stderr)
    end

    def quiet(name)
      registry = catalog(name)
      inline(registry: registry, source_root: dir, adapter: adapter(coverage: { "t1" => [first(registry)] }))
    end

    it "stays silent after a fully green warm-up" do
      stub_const("Warmquiet", Class.new)
      h = quiet("warmquiet")
      expect { h.warm!(["t1"]) }.not_to(output.to_stderr)
    end
  end

  describe "#isolate!" do
    it "wraps isolation in a rolled-back transaction when isolate_db is on" do
      FakeRails.unconnected(self)
      h = harness(adapter, isolate_db: true)
      h.__send__(:isolate!)
      expect(h.__send__(:isolation)).to(be_a(Kimera::Execution::CompositeIsolation))
    end

    it "leaves isolation alone by default even with ActiveRecord loaded", :aggregate_failures do
      FakeRails.unconnected(self)
      h = harness(adapter)
      h.__send__(:isolate!)
      expect(h.__send__(:isolation)).to(be_a(Kimera::Execution::Isolation))
      expect(h.__send__(:isolation)).not_to(be_a(Kimera::Execution::CompositeIsolation))
    end

    it "stays a no-op when isolate_db is on but ActiveRecord is absent", :aggregate_failures do
      hide_const("ActiveRecord") if defined?(ActiveRecord)
      h = harness(adapter, isolate_db: true)
      expect { h.__send__(:isolate!) }.not_to(raise_error)
      expect(h.__send__(:isolation)).not_to(be_a(Kimera::Execution::CompositeIsolation))
    end
  end

  it "stays silent on stderr when no progress is injected" do
    expect do
      h = described_class.build(registry: registry, adapter: adapter(coverage: { "t1" => [] }))
      h.__send__(:measure!)
    end.not_to(output.to_stderr)
  end

  describe "per-worker database isolation" do
    def database(jobs:)
      Kimera::Execution::WorkerDatabases.new(jobs: jobs)
    end

    def stub(before: nil, after: nil, cleanup: nil)
      par = Module.new
      par.define_singleton_method(:before_fork_hooks) { Array(before) }
      par.define_singleton_method(:after_fork_hooks) { Array(after) }
      par.define_singleton_method(:run_cleanup_hooks) { Array(cleanup) }
      stub_const("ActiveSupport::Testing::Parallelization", par)
      par
    end

    def parallelization(enabled)
      as = Module.new
      as.define_singleton_method(:parallelize_test_databases) { enabled }
      stub_const("ActiveSupport", as)
    end

    it "is off at jobs == 1 / without Rails parallelization", :aggregate_failures do
      expect(database(jobs: 1).active?).to(be(false))
      expect(database(jobs: 2).active?).to(be(false))
    end

    def callbacks
      before = 0
      after = []
      stub(before: -> { before += 1 }, after: ->(i) { after << i })
      db = database(jobs: 2)
      db.before_fork
      db.after_fork(3)
      [before, after]
    end

    it "runs the registered before/after fork hooks per worker when isolation is on", :aggregate_failures do
      before, after = callbacks
      expect(before).to(eq(1))
      expect(after).to(eq([3]))
    end

    def drain
      cleaned = []
      parallelization(true)
      stub(after: ->(_i) {}, cleanup: ->(i) { cleaned << i })
      fake_feature("active_record/test_databases")
      db = database(jobs: 2)
      db.before_exit(0)
      db.before_exit(nil)
      cleaned
    end

    it "runs the app's cleanup hooks with the worker's slot as it drains" do
      expect(drain).to(eq([0]))
    end

    def connected(connection)
      stub_const("ActiveRecord::Tasks::DatabaseTasks", FakeRails::Tasks.new(__FILE__))
      stub_const("ActiveRecord::ConnectionHandling::DEFAULT_ENV", -> { "test" })
      config = FakeRails::Config.new("postgresql", "app_test")
      stub_const("ActiveRecord::Base", FakeRails::Base.new(config, connection: connection))
      connection
    end

    it "empties the worker's database as it drains" do
      connection = connected(FakeRails::Connection.new("SQLite", %w[users posts]))
      drain
      expect(connection.said).to(eq([[:truncate_tables, "users", "posts"]]))
    end

    def scrub(adapter, truncate: nil)
      connection = connected(FakeRails::Connection.new(adapter, %w[users], truncate: truncate))
      cleaned = []
      stub(after: ->(_i) {}, cleanup: ->(index) { cleaned << index })
      fake_feature("active_record/test_databases")
      errors = StringIO.new
      Kimera::Execution::WorkerDatabases.new(jobs: 2, errors: errors).before_exit(0)
      [connection, errors.string, cleaned]
    end

    it "bounds how long a PostgreSQL teardown truncate waits for locks" do
      postgres, = scrub("PostgreSQL")
      expect(postgres.said).to(eq([[:execute, "SET lock_timeout = '5s'"], [:truncate_tables, "users"]]))
    end

    it "bounds how long a MySQL teardown truncate waits for locks" do
      mysql, = scrub("Mysql2")
      expect(mysql.said).to(include([:execute, "SET SESSION lock_wait_timeout = 5"]))
    end

    it "sets no lock bound on SQLite" do
      lite, = scrub("SQLite")
      expect(lite.said).to(eq([[:truncate_tables, "users"]]))
    end

    it "warns and still runs the app's cleanup hooks when the teardown truncate gives up", :aggregate_failures do
      _, errors, cleaned = scrub("PostgreSQL", truncate: RuntimeError.new("lock timeout"))
      expect(errors).to(eq("kimera: could not empty the worker's test database (RuntimeError: lock timeout)\n"))
      expect(cleaned).to(eq([0]))
    end

    def unisolated
      connection = connected(FakeRails::Connection.new("SQLite", %w[users]))
      parallelization(true)
      cleaned = []
      stub(after: ->(_i) {}, cleanup: ->(i) { cleaned << i })
      database(jobs: 1).before_exit(0)
      [connection, cleaned]
    end

    it "leaves the shared database and the app's teardown hooks alone when isolation is off", :aggregate_failures do
      connection, cleaned = unisolated
      expect([connection.said, cleaned]).to(eq([[], []]))
    end

    def recordless
      hide_const("ActiveRecord") if defined?(ActiveRecord)
      parallelization(true)
      cleaned = []
      stub(after: ->(_i) {}, cleanup: ->(i) { cleaned << i })
      errors = StringIO.new
      Kimera::Execution::WorkerDatabases.new(jobs: 2, errors: errors).before_exit(0)
      [errors.string, cleaned]
    end

    it "runs the app's teardown hooks without a warning when Active Record is absent", :aggregate_failures do
      errors, cleaned = recordless
      expect(errors).to(be_empty)
      expect(cleaned).to(eq([0]))
    end

    it "never runs a nil-slot worker's after-fork hook (injected/test spawners)" do
      stub(after: ->(_i) { raise(RuntimeError, "should not run") })
      expect { database(jobs: 2).after_fork(nil) }.not_to(raise_error)
    end

    it "turns on only for jobs > 1 with Rails parallel test databases enabled", :aggregate_failures do
      parallelization(true)
      stub(after: ->(_i) {})
      expect(database(jobs: 1).active?).to(be(false))
      expect(database(jobs: 2).active?).to(be(true))
    end

    it "stays off when the app registered no fork hooks at all" do
      parallelization(true)
      stub(after: [])
      expect(database(jobs: 2).active?).to(be(false))
    end

    def registration
      parallelization(true)
      stub(after: [])
      FakeRails.unconnected(self)
      registered = fake_feature("active_record/test_databases")
      yield(database(jobs: 2))
      loaded?(registered).tap { $LOADED_FEATURES.delete(registered) }
    end

    it "loads Rails' own hook registration before deciding, on each side of the fork", :aggregate_failures do
      expect(registration { |db| db.before_fork(FakeConnections.new) }).to(be(true))
      expect(registration { |db| db.after_fork(0) }).to(be(true))
      expect(registration { |db| db.before_exit(0) }).to(be(true))
    end

    def skip
      calls = []
      parallelization(false)
      stub(after: ->(i) { calls << i })
      database(jobs: 2).after_fork(3)
      calls
    end

    it "skips the after-fork hooks entirely when isolation is off" do
      expect(skip).to(be_empty)
    end

    def forking
      before = []
      parallelization(true)
      stub(before: -> { before << :before }, after: ->(_i) {})
      driver = described_class.build(registry: registry, adapter: adapter, jobs: 2).__send__(:driver)
      reap(*driver.spawner(:serve).call(0).first(3))
      [before.dup, fleet(driver, before)]
    end

    def reap(pid, request, response)
      request.close
      response.read
      response.close
      Process.wait(pid)
    end

    def fleet(driver, before)
      listeners = Kimera::Execution::WorkerPool::Listeners.new(resolve: ->(_m) {}, lost: ->(*) {}, trace: nil)
      driver.drive([], driver.spawner(:serve), listeners)
      before
    end

    it "runs the parent-side before-fork hook once per fleet, not per spawned worker", :aggregate_failures do
      spawned, driven = forking
      expect(spawned).to(eq([]))
      expect(driven).to(eq([:before]))
    end

    def worker_id(jobs)
      test_case = Class.new { class << self; attr_accessor :parallel_worker_id; end }
      stub_const("ActiveSupport::TestCase", test_case)
      stub(after: ->(_i) {})
      database(jobs: jobs).after_fork(4)
      test_case.parallel_worker_id
    end

    it "sets ActiveSupport::TestCase.parallel_worker_id to the slot in a parallel worker", :aggregate_failures do
      expect(worker_id(2)).to(eq(4))
      expect(worker_id(1)).to(be_nil)
    end

    it "leaves a Rails without parallel_worker_id as it is" do
      stub_const("ActiveSupport::TestCase", Class.new)
      stub(after: ->(_i) {})
      expect { database(jobs: 2).after_fork(4) }.not_to(raise_error)
    end

    def slot
      parallelization(true)
      reader, writer = IO.pipe
      stub(before: -> {}, after: ->(i) { writer.puts(i) })
      paired.run(ids: [ids.first])
      writer.close
      reader.read.tap { reader.close }
    end

    def paired
      covered = adapter(coverage: { "t1" => [ids.first] })
      described_class.build(registry: registry, jobs: 2, soft_timeout: nil, adapter: covered)
    end

    it "hands a real pool worker its slot index for the after-fork hooks" do
      expect(slot).to(eq("0\n"))
    end

    it "stays off when the app disabled parallel test databases" do
      parallelization(false)
      stub(after: ->(_i) {})
      expect(database(jobs: 2).active?).to(be(false))
    end

    it "registers nothing, and warns nothing, when ActiveRecord is absent" do
      expect { database(jobs: 2).__send__(:register!) }.not_to(output.to_stderr)
    end

    def cleanup
      cleaned = []
      stub(after: [], cleanup: -> { cleaned << :cleaned })
      database(jobs: 2).before_exit(0)
      cleaned
    end

    it "skips the cleanup hooks when isolation is off" do
      expect(cleanup).to(be_empty)
    end
  end

  describe "#verify!" do
    include_context("with an inline zygote")

    def harness(adapter, **) = inline(registry: registry, adapter: adapter, **)

    it "passes silently when the suite is green" do
      h = harness(adapter(coverage: { "t1" => [] }))
      expect { h.__send__(:verify!) }.not_to(raise_error)
    end

    it "notes the whole-suite run as a phase of its own" do
      progress = journal
      harness(adapter(coverage: { "t1" => [] }), progress: progress).__send__(:verify!)
      expect(progress.events).to(eq([[:note, "baseline (whole suite, no coverage)"]]))
    end

    it "raises BaselineFailure when a test fails" do
      h = harness(adapter(coverage: { "t1" => [], "t2" => [] }, failing: ["t1"]))
      expect { h.__send__(:verify!) }.to(raise_error(Kimera::Execution::BaselineFailure, /t1/))
    end

    it "still gates a failing suite that re-selects a mutant" do
      h = harness(reselecting(coverage: { "t1" => [] }, failing: ["t1"]))
      expect { h.__send__(:verify!) }.to(raise_error(Kimera::Execution::BaselineFailure, /t1/))
    end

    it "stays silent for a green suite that re-selects a mutant" do
      h = harness(reselecting(coverage: { "t1" => [] }))
      expect { h.__send__(:verify!) }.not_to(raise_error)
    end

    def red
      Class.new(Kimera::Frameworks::Suite) do
        def source(_files) = self
        def test_ids = ["t1"]
        def run(_ids) = Kimera::Frameworks::RunOutcome.new(passed: false, failed_ids: ["t1"])
      end.new
    end

    def error
      harness(red).__send__(:verify!)
      raise(RuntimeError, "expected BaselineFailure")
    rescue Kimera::Execution::BaselineFailure => error
      error
    end

    def message
      "baseline suite is not green: t1\n  " \
        "reproduce without kimera: rspec t1 --order defined"
    end

    it "renders exactly the summary and hint when no assertion messages exist" do
      expect(error.message).to(eq(message))
    end
  end

  describe "Triage#tiers, the safe tier" do
    it "holds an ordinary point and an unknown id" do
      expect(triage(registry).tiers([ids.first, 999_999]).first).to(eq([ids.first, 999_999]))
    end

    it "is false for a memoized (schema-unsafe) point" do
      memo = Kimera::RegistryScan.new.source(<<~RUBY, file: "m.rb")
        def total(a, b)
          @t ||= compute(a > b)
        end
      RUBY
      unsafe = memo.each.first.first.to_i
      expect(triage(memo).tiers([unsafe]).first).to(be_empty)
    end
  end

  describe "result helpers" do
    let(:verdicts) { Kimera::Execution::Verdicts.new(registry) }
    let(:reloadverdict) { reloader(adapter) }

    it "builds a timeout result carrying the file", :aggregate_failures do
      expect(verdicts.timeout(ids.first, 5.0).status).to(eq(:timeout))
      expect(verdicts.timeout(ids.first, 5.0).file).to(eq("calc.rb"))
    end

    it "builds an unjudged result carrying the file and detail", :aggregate_failures do
      error = verdicts.unjudged(ids.first, "nope")
      expect(error.status).to(eq(:harness_error))
      expect(error.file).to(eq("calc.rb"))
      expect(error.detail).to(eq("nope"))
    end

    it "treats a missing output line as a harness_error: no result", :aggregate_failures do
      v = reloadverdict.__send__(:verdict, 7, nil)
      expect(v.status).to(eq(:harness_error))
      expect(v.detail).to(include("no result"))
    end

    it "names the signal that killed a reload worker with no result" do
      status = Process.wait2(Process.spawn(Gem.ruby, "-e", "Process.kill(:KILL, Process.pid)")).last
      v = reloadverdict.__send__(:verdict, 7, nil, status)
      expect(v.detail).to(eq("reload worker produced no result (died on signal 9)"))
    end

    it "treats a torn output line as a harness_error: unparseable", :aggregate_failures do
      v = reloadverdict.__send__(:verdict, 7, "{torn")
      expect(v.status).to(eq(:harness_error))
      expect(v.detail).to(include("unparseable"))
    end

    it "maps valid JSON to a killed result with the mutant id", :aggregate_failures do
      v = reloadverdict.__send__(:verdict, 7, JSON.generate(id: 7, status: "killed", ms: 1, fails: []))
      expect(v.status).to(eq(:killed))
      expect(v.mutant_id).to(eq(7))
    end

    def worker
      { "id" => ids.first, "status" => "killed", "ms" => 1.2, "fails" => ["t1"], "cover" => ["t1"] }
    end

    it "maps a worker message into a MutantResult", :aggregate_failures do
      result = verdicts.parse(worker)
      expect(result.status).to(eq(:killed))
      expect(result.file).to(eq("calc.rb"))
      expect(result.failing_tests).to(eq(["t1"]))
    end

    it "hands malformed JSON to the block parse is given" do
      expect(harness(adapter).__send__(:parse, "not json") { :unparsed }).to(eq(:unparsed))
    end
  end

  describe "Triage#reclassified" do
    def result(id, status, file)
      Kimera::MutantResult.new(mutant_id: id, status: status, file: file, duration: 0.0)
    end

    let(:results) do
      {
        1 => result(1, :error, "lib/kimera/execution/shift.rb"),
        2 => result(2, :timeout, "lib/kimera/frameworks/rspec_suite.rb"),
        3 => result(3, :killed, "lib/kimera/execution/shift.rb"),
        4 => result(4, :error, "app/models/user.rb"),
        5 => result(5, :survived, "lib/kimera/execution/shift.rb"),
        6 => result(6, :survived, "app/models/user.rb")
      }
    end

    let(:reclassified) { triage(registry).reclassified(results) }

    it "downgrades a runner error/timeout to isolated_only", :aggregate_failures do
      expect(reclassified[1].status).to(eq(:isolated_only))
      expect(reclassified[2].status).to(eq(:isolated_only))
    end

    it "leaves a genuine runner kill and ordinary-file verdicts alone", :aggregate_failures do
      expect(reclassified[3].status).to(eq(:killed))
      expect(reclassified[4].status).to(eq(:error))
      expect(reclassified[6].status).to(eq(:survived))
    end

    it "downgrades an unfalsifiable warm survivor on the runner to isolated_only" do
      expect(reclassified[5].status).to(eq(:isolated_only))
    end

    it "explains the downgrade: self-crash vs unfalsifiable survivor, with the original status", :aggregate_failures do
      expect(reclassified[1].detail).to(include("--isolated"))
      expect(reclassified[1].detail).to(include("self-crash"))
      expect(reclassified[1].detail).to(include("warm error"))
      expect(reclassified[5].detail).to(include("unfalsifiable"))
    end
  end

  describe(Kimera::Execution::Priority) do
    def order(coverage, ids) = described_class.new(coverage).order(ids)

    it "orders mutants heaviest-covering-first (longest runs start earliest)" do
      expect(order({ 1 => %w[a], 2 => %w[a b c], 3 => %w[a b] }, [1, 2, 3])).to(eq([2, 3, 1]))
    end

    it "counts covering tests by int key, then string key, else zero" do
      expect(order({ 5 => %w[a b], "6" => %w[c] }, [8, 6, 5])).to(eq([5, 6, 8]))
    end

    it "treats every mutant as unit cost when no coverage map was built" do
      expect(order(nil, [5, 1, 3])).to(eq([5, 1, 3]))
    end
  end

  describe "Triage#tiers, the reload tier" do
    let(:mixed_registry) do
      Kimera::RegistryScan.new(
        operators: Kimera::Operators.build(keys: %w[comparison rails_validation])
      ).source(<<~RUBY, file: "m.rb")
        class M
          validates :name, presence: true
          def ok?(x, y)
            x > y
          end
        end
      RUBY
    end

    it "is false for a class-body point and true for a method-body point", :aggregate_failures do
      body = mixed_registry.each.find { |_m, p| p.reasons(Kimera::Reason.class_body).any? }.first.to_i
      method = mixed_registry.each.find { |_m, p| p.reasons(Kimera::Reason.class_body).none? }.first.to_i
      mixed_registry.index.fetch(method).mark!(Kimera::Reason.unsafe("memoized"))
      expect(triage(mixed_registry).tiers([body, method]).drop(1)).to(eq([[method], [body]]))
    end

    it "puts an unknown id (no registry point) in the safe tier" do
      expect(triage(registry).tiers([10_000_000])).to(eq([[10_000_000], [], []]))
    end

    it "is false for an unmutatable method-body point" do
      mutant, point = mixed_registry.each.find { |_m, p| p.reasons(Kimera::Reason.class_body).none? }
      point.mark!(Kimera::Reason.unmutatable("kimera could not write its guard"))
      expect(triage(mixed_registry).tiers([mutant.to_i]).last).to(eq([mutant.to_i]))
    end
  end

  describe "unmutatable mutants" do
    def unmutatable
      registry = Kimera::RegistryScan.new.source("def gt(a, b)\n  a > b\nend\n", file: "u.rb")
      registry.to_a.each { |point| point.mark!(Kimera::Reason.unmutatable("schemata setup failed (boom)")) }
      progress = journal
      ids = registry.each.map { |mutant, _point| mutant.to_i }
      [described_class.build(registry: registry, adapter: adapter, progress: progress).run(ids: ids), progress]
    end

    it "reports them as :unmutatable, with the reason, without evaluating them", :aggregate_failures do
      report, progress = unmutatable
      expect(report.to_a.map(&:status).uniq).to(eq([:unmutatable]))
      expect(report.to_a.first.detail).to(eq("unmutatable: schemata setup failed (boom)"))
      expect(report.to_a.first.file).to(eq("u.rb"))
      expect(progress.events).to(include(%i[tick unmutatable]))
    end

    it "keeps them out of no_coverage and the score, but names them", :aggregate_failures do
      report, = unmutatable
      expect(report.select { it.status?(:no_coverage) }).to(be_empty)
      expect(report.score.to_f).to(eq(1.0))
      expect(report.score.to_s).to(include("unmutatable=2"))
    end
  end

  describe "#warm!" do
    include_context("with an inline zygote")

    let(:dir) { Dir.mktmpdir }

    after { FileUtils.remove_entry(dir) }

    def stubbed(name)
      stub_const(name, Class.new)
      registry = fixture(name)
      [registry, registry.each.map { |m, _p| m.to_i }]
    end

    def fixture(name)
      File.write(File.join(dir, "#{name.downcase}.rb"), <<~RUBY)
        class #{name}
          def gt(a, b)
            a > b
          end
        end
      RUBY
      Kimera::RegistryScan.new(root: dir).build([File.join(dir, "#{name.downcase}.rb")])
    end

    def touching(mids)
      Class.new(Kimera::Frameworks::Suite) do
        define_method(:initialize) { |m| @mids = m }
        def source(_files) = self
        def test_ids = ["t1"]
        define_method(:run) do |_ids|
          @mids.each { |m| Kimera::RUNTIME.active?(m) }
          Kimera::Frameworks::RunOutcome.new(passed: true, failed_ids: [])
        end
      end.new(mids)
    end

    def mutants
      registry = fixture("WarmTarget")
      ids = registry.each.map { |m, _p| m.to_i }
      h = inline(registry: registry, adapter: touching(ids), source_root: dir)
      [h.warm!(["t1"]), ids, h.survey.coverage]
    end

    it "loads the suite, overlays schemata, and returns the live mutant ids", :aggregate_failures do
      stub_const("WarmTarget", Class.new)
      live, ids, coverage = mutants
      expect(live).to(match_array(ids))
      expect(coverage).not_to(be_empty)
    end

    def plain
      Class.new(Kimera::Frameworks::Suite) do
        def source(_files) = self
        def test_ids = ["t1"]
        def run(_ids) = Kimera::Frameworks::RunOutcome.new(passed: true, failed_ids: [])
      end.new
    end

    def ordered(mids)
      Class.new(Kimera::Frameworks::Suite) do
        define_method(:initialize) { |m| @mids = m }
        def source(_files) = self
        def test_ids = %w[t1 t2]
        define_method(:run) do |ids|
          @mids.each { |m| Kimera::RUNTIME.active?(m) } if ids.size > 1
          Kimera::Frameworks::RunOutcome.new(passed: true, failed_ids: [])
        end
      end.new(mids)
    end

    def revisits(registry) = registry.to_a.map { PointVerdict.new(it).revisit }.uniq

    def in_order
      registry, ids = stubbed("WarmOrdered")
      progress = journal
      h = inline(registry: registry, adapter: ordered(ids), source_root: dir, progress: progress)
      h.warm!(%w[t1 t2])
      { events: progress.events, covered: h.survey.coverage.slice(*ids).values.flatten, revisits: revisits(registry) }
    end

    it "notes the baseline run of the whole suite in order" do
      expect(in_order[:events]).to(include([:note, "baseline (whole suite, in order)"]))
    end

    it "sends a mutant only the suite run in order reaches to a second look" do
      expect(in_order).to(include(covered: [], revisits: [Kimera::Reason::ORDER_REASON]))
    end

    def racing(mids)
      Class.new(Kimera::Frameworks::Suite) do
        define_method(:initialize) { |m| @mids = m }
        def source(_files) = self
        def test_ids = %w[slow fast]
        define_method(:run) do |ids|
          sleep(0.05) if ids == ["slow"]
          hit = @mids.map { |m| Kimera::RUNTIME.active?(m) }.any?
          Kimera::Frameworks::RunOutcome.new(passed: !hit, failed_ids: hit ? ids : [])
        end
      end.new(mids)
    end

    def screening(name, flaky)
      stub_const(name, Class.new)
      registry = fixture(name)
      ids = registry.each.map { |m, _p| m.to_i }
      progress = journal
      h = inline(registry: registry, adapter: racing(ids), **screened(registry, flaky, progress))
      h.warm!(%w[t1], scope: ids)
      [h.run(ids: ids).to_a, ids, progress.events]
    end

    def screened(registry, flaky, progress)
      filter = Kimera::Execution::TestFilter.new(registry: registry, flaky: flaky)
      { source_root: dir, soft_timeout: nil, filter: filter, progress: progress }
    end

    def shaking(mids)
      Class.new(Kimera::Frameworks::Suite) do
        define_method(:initialize) do |m|
          super()
          @mids = m
        end
        def source(_files) = self
        def test_ids = %w[steady shaky]
        define_method(:run) do |ids|
          hit = @mids.map { |m| Kimera::RUNTIME.active?(m) }.any? || (ids == ["shaky"] && ENV["KIMERA_SEED"] == "6")
          Kimera::Frameworks::RunOutcome.new(passed: !hit, failed_ids: hit ? ids : [])
        end
      end.new(mids)
    end

    def shaken
      registry, ids = stubbed("WarmShaky")
      filter = Kimera::Execution::TestFilter.new(registry: registry)
      settings = { source_root: dir, soft_timeout: nil, filter: filter, flaky_runs: 1, seed: 5 }
      h = inline(registry: registry, adapter: shaking(ids), **settings)
      [h.tap { h.warm!(%w[t1], scope: ids) }, ids]
    end

    it "reruns the covering tests under other seeds and names the test that changed its result" do
      h, = shaken
      flaky = h.survey.noted(Kimera::RunReport.new(results: [])).notes.to_h["flaky"]
      expect([flaky["flaky"].map { |flake| flake["test"] }, flaky["seeds"]]).to(eq([["shaky"], [6]]))
    end

    it "lets no test that changed its result kill" do
      h, ids = shaken
      expect(h.run(ids: ids).to_a.map(&:failing_tests).uniq).to(eq([["steady"]]))
    end

    it "lets only the tests a screen keeps kill a warm mutant", :aggregate_failures do
      results, ids, = screening("WarmScreened", ["fast"])
      expect(results.map(&:failing_tests).uniq).to(eq([["slow"]]))
      expect(results.map(&:mutant_id)).to(match_array(ids))
    end

    it "settles, counted in the progress, each warm mutant the screen leaves no test", :aggregate_failures do
      results, ids, events = screening("WarmSettled", %w[fast slow])
      expect(results.map(&:status).uniq).to(eq([:no_coverage]))
      expect(results.map(&:detail).uniq).to(eq(["covered only by flaky test(s), which never kill: slow, fast"]))
      expect(events).to(include([:start, ids.size, "mutants"]))
      expect(events.count { |event| event == %i[tick no_coverage] }).to(eq(ids.size))
    end

    it "records every killing test of a warm mutant under test quality, and the same verdicts" do
      registry, ids = stubbed("WarmCensus")
      h = inline(registry: registry, adapter: racing(ids), source_root: dir, soft_timeout: nil, test_quality: true)
      h.warm!(%w[t1], scope: ids)
      results = h.run(ids: ids).to_a
      expect(results.map { |result| [result.status, result.failing_tests, result.killing_tests] }.uniq)
        .to(eq([[:killed, ["fast"], %w[slow fast]]]))
    end

    it "kills each mutant with the covering test the baseline timed fastest", :aggregate_failures do
      registry, ids = stubbed("WarmRacing")
      h = inline(registry: registry, adapter: racing(ids), source_root: dir, soft_timeout: nil)
      h.warm!(%w[t1], scope: ids)
      expect(h.survey.__send__(:timings).fetch("slow")).to(be > h.survey.__send__(:timings).fetch("fast"))
      expect(h.run(ids: ids).to_a.map(&:failing_tests).uniq).to(eq([["fast"]]))
    end

    def scoped(name, adapter, scope)
      registry = fixture(name)
      progress = journal
      ids = registry.each.map { |m, _p| m.to_i }
      described_class
        .build(registry: registry, adapter: adapter.call(ids), source_root: dir, progress: progress)
        .warm!(%w[t1 t2], scope: scope.call(registry))
      [progress.events, revisits(registry)]
    end

    it "runs the suite in order when a mutant in scope has no single test's coverage", :aggregate_failures do
      stub_const("WarmScoped", Class.new)
      events, reasons = scoped("WarmScoped", method(:ordered), ->(registry) { registry.each.map { |m, _p| m.to_i } })
      expect(events).to(include([:note, "baseline (whole suite, in order)"]))
      expect(reasons).to(eq([Kimera::Reason::ORDER_REASON]))
    end

    it "skips the run in order when every mutant in scope is covered", :aggregate_failures do
      stub_const("WarmCovered", Class.new)
      events, reasons = scoped("WarmCovered", method(:touching), ->(registry) { registry.each.map { |m, _p| m.to_i } })
      expect(events).not_to(include([:note, "baseline (whole suite, in order)"]))
      expect(reasons).to(eq([nil]))
    end

    it "skips the run in order when no mutant is in scope", :aggregate_failures do
      stub_const("WarmOutside", Class.new)
      events, reasons = scoped("WarmOutside", method(:ordered), ->(_) { [] })
      expect(events).not_to(include([:note, "baseline (whole suite, in order)"]))
      expect(reasons).to(eq([nil]))
    end

    it "runs the plain baseline check when coverage is disabled" do
      stub_const("WarmNoCov", Class.new)
      h = inline(registry: fixture("WarmNoCov"), adapter: plain, source_root: dir)
      expect { h.without_coverage!(["t1"]) }.not_to(raise_error)
    end
  end

  describe "leak reporting in the scheduler" do
    it "records a leak message emitted by a pool worker" do
      spawner = responder(status: "killed", extra: "state leaked")
      report = harness(adapter, spawner: spawner).run(ids: ids)
      expect(report.notes.to_h["leaks"].map(&:detail)).to(include("state leaked"))
    end
  end

  describe "self-verdict reclassification in #run" do
    def survivor
      registry = Kimera::RegistryScan.new.source(<<~RUBY, file: "kimera/execution/shift.rb")
        def a(x, y)
          x > y
        end
      RUBY
      rid = registry.each.map { |m, _p| m.to_i }.first
      report =
        described_class.build(registry: registry, adapter: adapter, spawner: responder(status: "survived"))
          .run(ids: [rid])
      report.to_a.find { |r| r.mutant_id == rid }
    end

    it "downgrades a warm survivor on a harness-critical file", :aggregate_failures do
      result = survivor
      expect(result.status).to(eq(:isolated_only))
      expect(result.detail).to(include("unfalsifiable warm survivor"))
    end
  end

  def unsafe_id(registry, label = nil)
    registry.each.find { |mutant, point| !point.safe? && (label.nil? || mutant.to_s == label) }.first.to_i
  end

  def writing(dir, klass)
    File.write(File.join(dir, "#{klass.downcase}.rb"), <<~RUBY)
      class #{klass}
        def gt(a, b)
          a > b
        end
        def memo(a, b)
          @memo ||= (a < b)
        end
      end
    RUBY
    Kimera::RegistryScan.new(root: dir).build([File.join(dir, "#{klass.downcase}.rb")])
  end

  def observer(klass)
    Class.new(Kimera::Frameworks::Suite) do
      define_method(:initialize) { @klass = klass }
      def source(_files) = self
      def test_ids = ["t1"]
      define_method(:run) do |_ids|
        object = Object.const_get(@klass).new
        ok = (object.gt(2, 1) == true) && (object.memo(1, 2) == true)
        Kimera::Frameworks::RunOutcome.new(passed: ok, failed_ids: ok ? [] : ["t1"])
      end
    end.new
  end

  describe "end-to-end fast path with the real pool worker" do
    let(:dir) { Dir.mktmpdir }

    after { FileUtils.remove_entry(dir) }

    def outcome
      h = described_class.build(
        registry: writing(dir, "HarnessE2E"), adapter: observer("HarnessE2E"),
        source_root: dir, soft_timeout: nil, leak_every: 0
      )
      h.warm!(["t1"])
      h.run
    end

    it "warms up and kills the schema-safe mutants via a pool worker", :aggregate_failures do
      stub_const("HarnessE2E", Class.new)
      report = outcome
      expect(report.to_a).not_to(be_empty)
      expect(report.select { it.status?(:error) }).to(be_empty)
      expect(report.select(&:killed?)).not_to(be_empty)
    end
  end

  describe "#evaluate_reload (reload fallback child logic, run in-process)" do
    def errand(id, tests = ["t1"])
      silent = Kimera::Execution::Reload::Errand.new(id, tests, nil, nil)
      [id, silent.tap { |e| e.define_singleton_method(:tick) { |test| ran << test } }]
    end

    let(:dir) { Dir.mktmpdir }

    after { FileUtils.remove_entry(dir) }

    def classification
      registry = writing(dir, "HarnessReload")
      load(File.join(dir, "harnessreload.rb"))
      reloading = reloader(observer("HarnessReload"), catalog: registry, root: dir)
      reloading.__send__(:evaluate, *errand(unsafe_id(registry, "< => >")))
    end

    it "bakes the mutation, reloads, and classifies the outcome" do
      stub_const("HarnessReload", Class.new)
      status, = classification
      expect(status).to(eq(:killed))
    end

    def required
      stub_const("HarnessRequired", Class.new)
      writing(dir, "HarnessRequired")
      path = File.join(dir, "harnessrequired.rb")
      File.write(path, File.read(path).sub("class HarnessRequired\n", "\\0  @loads = (@loads || 0) + 1\n"))
      Kimera::RegistryScan.new(root: dir).build([path]).tap { require(path) }
    end

    it "re-runs only the reloaded method of a file that was already required", :aggregate_failures do
      registry = required
      status, = reloader(observer("HarnessRequired"), catalog: registry, root: dir)
        .__send__(:evaluate, *errand(unsafe_id(registry, "< => >")))
      expect(status).to(eq(:killed))
      expect(HarnessRequired.instance_variable_get(:@loads)).to(eq(1))
    end

    def aliased_verdict(registry)
      aliases = Kimera::Execution::Aliases.new([File.join(dir, "harnessaliased.rb")]).tap { |a| a.follow { :captured } }
      runner = reloader(observer("HarnessAliasing"), catalog: registry, root: dir, aliases: aliases)
      runner.__send__(:evaluate, *errand(unsafe_id(registry, "< => >")))
    end

    it "reaches the reloaded method through an alias declared in another file" do
      stub_const("HarnessAliased", Class.new)
      registry = writing(dir, "HarnessAliased")
      load(File.join(dir, "harnessaliased.rb"))
      aliasing("HarnessAliasing", HarnessAliased)
      expect(aliased_verdict(registry).first).to(eq(:killed))
    end

    def reload(name)
      stub_const(name, Class.new)
      registry = writing(dir, name)
      load(File.join(dir, "#{name.downcase}.rb"))
      [registry, registry.each.map { |m, _p| m.to_i }.find { |id| !registry.index[id].safe? }]
    end

    def calling(name) = -> { Object.const_get(name).new.memo(1, 2) }

    def plain(passed:, reach: -> {})
      Class.new(Kimera::Frameworks::Suite) do
        define_method(:initialize) { @passed = passed }
        def source(_files) = self
        def test_ids = ["t1"]
        define_method(:run) do |_ids|
          reach.call
          Kimera::Frameworks::RunOutcome.new(passed: @passed, failed_ids: @passed ? [] : ["t1"])
        end
      end.new
    end

    it "classifies a green re-selecting suite as survived" do
      registry, unsafe = reload("HarnessReselGreen")
      suite = plain(passed: true, reach: calling("HarnessReselGreen"))
      runner = reloader(suite, catalog: registry, root: dir, isolation: reselection)
      expect(runner.__send__(:evaluate, *errand(unsafe))).to(eq([:survived, []]))
    end

    it "classifies a green suite that never calls the mutant's method as uncovered" do
      registry, unsafe = reload("HarnessReloadUncalled")
      runner = reloader(plain(passed: true), catalog: registry, root: dir, isolation: reselection)
      uncalled = Kimera::Execution::Reload::UNCALLED
      expect(runner.__send__(:evaluate, *errand(unsafe))).to(eq([:no_coverage, [], uncalled]))
    end

    def counting(tests, failing, calls, reach: {})
      Class.new(Kimera::Frameworks::Suite) do
        define_method(:source) { |_files| self }
        define_method(:test_ids) { tests }
        define_method(:run) do |ids|
          calls << ids
          ids.each { |id| reach[id]&.call }
          failed = ids & failing
          Kimera::Frameworks::RunOutcome.new(passed: failed.empty?, failed_ids: failed)
        end
      end.new
    end

    it "runs one test at a time and stops at the first failure", :aggregate_failures do
      registry, unsafe = reload("HarnessReloadFast")
      calls = []
      runner = reloader(counting(%w[t1 t2 t3], ["t2"], calls), catalog: registry, root: dir, isolation: reselection)
      expect(runner.__send__(:evaluate, *errand(unsafe, %w[t1 t2 t3]))).to(eq([:killed, ["t2"]]))
      expect(calls).to(eq([["t1"], ["t2"]]))
    end

    it "reports the tests that called its method and how long it took" do
      registry, unsafe = reload("HarnessReloadReport")
      suite = counting(%w[t1 t2 t3 t4], ["t3"], [], reach: { "t2" => calling("HarnessReloadReport") })
      runner = reloader(suite, catalog: registry, root: dir, isolation: reselection)
      report = JSON.parse(runner.__send__(:report, *errand(unsafe, %w[t1 t2 t3 t4])))
      expect(report.values_at("status", "fails", "cover", "ms")).to(match(["killed", ["t3"], ["t2"], be >= 0]))
    end

    def ticked
      registry, unsafe = reload("HarnessReloadTick")
      reader, writer = IO.pipe
      errand = Kimera::Execution::Reload::Errand.new(unsafe, %w[t1 t2 t3], reader, writer)
      reloader(counting(%w[t1 t2 t3], [], []), catalog: registry, root: dir, isolation: reselection)
        .__send__(:evaluate, unsafe, errand)
      writer.close
      [errand.ran, reader.read.lines.size]
    end

    it "ticks the errand before every test it runs" do
      expect(ticked).to(eq([%w[t1 t2 t3], 3]))
    end

    it "orders tests covering the mutant's method, then its file, before the rest" do
      registry, unsafe = reload("HarnessReloadOrder")
      point = registry.index[unsafe]
      other = registry.to_h.fetch(point.file, []).find { |p| p.method_name != point.method_name }
      kinship = Kimera::Execution::Kinship.new(registry, { other.ids.first => ["t4"], point.ids.first => %w[t3 t9] })
      expect(kinship.order(unsafe, %w[t1 t2 t3 t4])).to(eq(%w[t3 t4 t1 t2]))
    end

    it "keeps the suite order for an unknown mutant or missing coverage", :aggregate_failures do
      registry, unsafe = reload("HarnessReloadAlone")
      expect(Kimera::Execution::Kinship.new(registry, nil).order(unsafe, %w[t2 t1])).to(eq(%w[t2 t1]))
      expect(Kimera::Execution::Kinship.new(registry, {}).order(10_000_000, %w[t2 t1 t2])).to(eq(%w[t2 t1]))
    end

    it "classifies a failing re-selecting suite as killed with its failures" do
      registry, unsafe = reload("HarnessReselRed")
      runner = reloader(plain(passed: false), catalog: registry, root: dir, isolation: reselection)
      expect(runner.__send__(:evaluate, *errand(unsafe))).to(eq([:killed, ["t1"]]))
    end

    def cold
      registry, unsafe = reload("HarnessReloadCold")
      progress = journal
      [
        described_class.build(
          registry: registry, adapter: plain(passed: true, reach: calling("HarnessReloadCold")),
          source_root: dir, soft_timeout: nil, progress: progress
        ).run(ids: [unsafe]),
        progress
      ]
    end

    def screened(name, flaky)
      registry, unsafe = reload(name)
      filter = Kimera::Execution::TestFilter.new(registry: registry, flaky: flaky)
      settings = { source_root: dir, soft_timeout: nil, coverage: {}, filter: filter }
      suite = counting(%w[t1 t2], ["t1"], [], reach: %w[t1 t2].to_h { |test| [test, calling(name)] })
      described_class.build(registry: registry, adapter: suite, **settings).run(ids: [unsafe]).to_a.first
    end

    it "runs a reloaded mutant against the tests the screen keeps, or settles it when it keeps none",
      :aggregate_failures do
      expect(screened("HarnessReloadUnscreened", []).status).to(eq(:killed))
      expect(screened("HarnessReloadScreened", ["t1"]).status).to(eq(:survived))
      settled = screened("HarnessReloadSettled", %w[t1 t2])
      expect(
        [
          settled.status,
          settled.detail
        ]
      ).to(eq([:no_coverage, "covered only by flaky test(s), which never kill: t1, t2"]))
    end

    it "runs the reload path end-to-end without a prior warm-up", :aggregate_failures do
      report, progress = cold
      expect(report.to_a.first.status).to(eq(:survived))
      expect(progress.events).to(include(%i[tick survived]))
    end

    def unwritten = failing_scribe { KeyError.new("key not found: :lvar") }

    it "reports a mutant kimera can't bake as unmutatable, with the reason", :aggregate_failures do
      unwritten
      report, progress = cold
      expect(report.to_a.first).to(
        have_fields(
          status: :unmutatable,
          detail: "unmutatable: kimera could not write its bake (KeyError: key not found: :lvar)"
        )
      )
      expect(progress.events).to(include(%i[tick unmutatable]))
    end

    def boom
      Class.new(Kimera::Frameworks::Suite) do
        def source(_files) = self
        def test_ids = ["t1"]
        def run(_ids) = raise(RuntimeError, "kaboom")
      end.new
    end

    def evaluation
      stub_const("HarnessBoom", Class.new)
      registry = writing(dir, "HarnessBoom")
      load(File.join(dir, "harnessboom.rb"))
      reloading = reloader(boom, catalog: registry, root: dir, isolation: reselection)
      reloading.__send__(:evaluate, *errand(unsafe_id(registry)))
    end

    it "captures an exception during reload as an :error result, saying where it happened", :aggregate_failures do
      status, fails, detail = evaluation
      expect([status, fails]).to(eq([:error, []]))
      expect(detail).to(start_with("#{Kimera::Execution::Reload::LOADING}RuntimeError: kaboom"))
    end

    it "classifies a bake kimera can't write as unmutatable, with the reason" do
      unwritten
      expect(evaluation).to(
        eq([:unmutatable, [], "unmutatable: kimera could not write its bake (KeyError: key not found: :lvar)"])
      )
    end
  end

  describe "#run_reload hard-deadline" do
    let(:dir) { Dir.mktmpdir }

    after { FileUtils.remove_entry(dir) }

    def hanging
      Class.new(Kimera::Frameworks::Suite) do
        def source(_files) = self
        def test_ids = ["t1"]
        def run(_ids) = sleep(30)
      end.new
    end

    def crashing
      Class.new(Kimera::Frameworks::Suite) do
        def source(_files) = self
        def test_ids = ["t1"]
        def run(_ids) = exit!(1)
      end.new
    end

    def timing(name, adapt, deadline:)
      stub_const(name, Class.new)
      registry = writing(dir, name)
      load(File.join(dir, "#{name.downcase}.rb"))
      clocked { reloader(adapt, catalog: registry, root: dir).run(unsafe_id(registry), deadline: deadline) }
    end

    def clocked
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      [yield, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started]
    end

    def hooking(marker)
      Class.new(Kimera::Frameworks::Suite) do
        def source(_files) = self
        def test_ids = ["t1"]
        define_method(:run) do |_ids|
          at_exit { File.write(marker, "ran") }
          Kimera::Frameworks::RunOutcome.new(passed: true, failed_ids: [])
        end
      end.new
    end

    it "ends a reload child without running the exit hooks it holds" do
      marker = File.join(dir, "exit-hook")
      timing("HarnessExitHook", hooking(marker), deadline: 30)
      expect(File).not_to(exist(marker))
    end

    it "hard-kills a reload child whose test overruns the deadline, as a timeout", :aggregate_failures do
      result, elapsed = timing("HarnessHang", hanging, deadline: 0.3)
      expect(result.status).to(eq(:timeout))
      expect(elapsed).to(be < 5)
    end

    def sluggish(tests, pause, name)
      Class.new(Kimera::Frameworks::Suite) do
        define_method(:source) { |_files| self }
        define_method(:test_ids) { tests }
        define_method(:run) do |_ids|
          sleep(pause)
          Object.const_get(name).new.memo(1, 2)
          Kimera::Frameworks::RunOutcome.new(passed: true, failed_ids: [])
        end
      end.new
    end

    it "restarts the deadline for every test the reload child runs", :aggregate_failures do
      result, elapsed = timing("HarnessSlow", sluggish(%w[t1 t2 t3 t4], 0.2, "HarnessSlow"), deadline: 0.5)
      expect(result.status).to(eq(:survived))
      expect(elapsed).to(be > 0.5)
    end

    it "notices an early-dead reload child immediately", :aggregate_failures do
      result, elapsed = timing("HarnessCrash", crashing, deadline: 30)
      expect(result.status).to(eq(:harness_error))
      expect(result.detail).to(eq("reload worker produced no result (exited 1)"))
      expect(elapsed).to(be < 5)
    end
  end

  describe "#run with a schema-unsafe mutant (real reload fork)" do
    let(:dir) { Dir.mktmpdir }

    after { FileUtils.remove_entry(dir) }

    def unsafe
      stub_const("HarnessUnsafe", Class.new)
      registry = writing(dir, "HarnessUnsafe")
      progress = journal
      h = described_class.build(
        registry: registry, adapter: observer("HarnessUnsafe"),
        source_root: dir, soft_timeout: nil, leak_every: 0,
        progress: progress
      )
      h.warm!(["t1"])
      unsafe = unsafe_id(registry)
      report = h.run(ids: [unsafe])
      [report.to_a.find { |r| r.mutant_id == unsafe }, progress]
    end

    it "routes the memoized mutant through the reload fallback", :aggregate_failures do
      result, = unsafe
      expect(result).not_to(be_nil)
      expect(result.status).to(satisfy { |status| %i[killed survived no_coverage].include?(status) })
    end

    def reached(registry)
      h = described_class.build(
        registry: registry, adapter: observer("HarnessReaching"), source_root: dir, soft_timeout: nil, leak_every: 0
      )
      h.warm!(["t1"])
      unsafe = registry.each.find { |m, p| !p.safe? && m.to_s == "< => >" }.first.to_i
      h.run(ids: [unsafe]).to_a.first.status
    end

    it "re-points an alias declared in another file at the reloaded mutant" do
      stub_const("HarnessReached", Class.new)
      registry = writing(dir, "HarnessReached")
      load(File.join(dir, "harnessreached.rb"))
      aliasing("HarnessReaching", HarnessReached)
      expect(reached(registry)).to(eq(:killed))
    end

    it "reports reload progress like the pool path and reaps the child", :aggregate_failures do
      result, progress = unsafe
      expect(progress.events).to(include([:tick, result.status]))
      expect { Process.wait }.to(raise_error(Errno::ECHILD))
    end
  end

  describe "#run partitioning" do
    it "evaluates only schema-safe mutants through the pool scheduler" do
      report = harness(adapter, spawner: responder(status: "killed")).run(ids: ids)
      expect(report.select(&:killed?).map(&:mutant_id)).to(match_array(ids))
    end
  end

  describe "kill-loop progress" do
    def killing
      progress = journal
      harness(adapter, spawner: responder(status: "killed"), progress: progress).run(ids: ids)
      progress
    end

    it "starts a mutants phase, ticks each verdict, and clears the line", :aggregate_failures do
      progress = killing
      expect(progress.events.first).to(eq([:start, ids.size, "mutants"]))
      expect(progress.events.count { |e| e == %i[tick killed] }).to(eq(ids.size))
      expect(progress.events.last).to(eq([:finish]))
    end

    it "evaluates every registry mutant when no explicit ids are given" do
      report = harness(adapter, spawner: responder(status: "killed")).run
      expect(report.select(&:killed?).map(&:mutant_id)).to(match_array(ids))
    end

    def hanging
      lambda do |_slot|
        forked do |request, response|
          if (line = request.gets)
            response.puts(JSON.generate(t: "start", id: JSON.parse(line)["id"]))
            response.flush
          end
          sleep(30)
          exit!(0)
        end
      end
    end

    def lost
      progress = journal
      [
        harness(adapter, spawner: hanging, progress: progress, hard_timeout: 0.3).run(ids: [ids.first]),
        progress
      ]
    end

    it "ticks lost mutants with their timeout/error status", :aggregate_failures do
      report, progress = lost
      expect(progress.events).to(include(%i[tick timeout]))
      expect(progress.events.last).to(eq([:finish]))
      expect(report.to_a.map(&:status)).to(eq([:timeout]))
    end
  end

  describe "default spawner" do
    def unstubbed
      harness(adapter(coverage: { "t1" => [ids.first] }), soft_timeout: nil).run(ids: [ids.first])
    end

    def terminating
      Class.new(Kimera::Frameworks::Suite) do
        def source(_files) = self
        def test_ids = ["t1"]

        def run(_ids)
          Process.kill("TERM", Process.pid)
          sleep(5)
        end
      end.new
    end

    it "reports the signal and exception that ended a real pool worker", :aggregate_failures do
      result = harness(terminating, soft_timeout: nil).run(ids: [ids.first]).to_a.first
      expect(result.status).to(eq(:harness_error))
      expect(result.detail).to(start_with("worker crashed before result: died on signal 15 (SIGTERM)\n"))
      expect(result.detail).to(include("\nSignalException: SIGTERM\n"))
      expect(result.detail).to(include("nothing trapped SIGTERM"))
    end

    it "forks a real serving pool worker when none is injected", :aggregate_failures do
      report = unstubbed
      expect(report.to_a.map(&:mutant_id)).to(eq([ids.first]))
      expect(report.to_a.first.status).to(eq(:survived))
      expect { Process.wait }.to(raise_error(Errno::ECHILD))
    end
  end

  describe "pool crash recovery" do
    def crashing(request, response)
      request.gets
      response.puts(JSON.generate(t: "crash", detail: "Boom: from the worker"))
      response.flush
      exit!(3)
    end

    def crash
      crashed = false
      lambda do |_slot|
        first = !crashed
        crashed = true
        forked do |request, response|
          first ? crashing(request, response) : serving(request, response) { |id| judged(response, id, "killed") }
          exit!(0)
        end
      end
    end

    let(:crashrecoveryreport) { harness(adapter, spawner: crash, jobs: 1).run(ids: ids.first(2)) }
    let(:byid) { crashrecoveryreport.to_a.to_h { |r| [r.mutant_id, r.status] } }

    it "charges the crashed id as an error and lets the replacement worker kill the rest", :aggregate_failures do
      expect(byid[ids[0]]).to(eq(:harness_error))
      expect(byid[ids[1]]).to(eq(:killed))
      expect(crashrecoveryreport.to_a.size).to(eq(2))
    end

    it "says how the crashed worker died and what it raised" do
      detail = crashrecoveryreport.to_a.find { |r| r.mutant_id == ids[0] }.detail
      expect(detail).to(eq("worker crashed before result: exited 3\nBoom: from the worker"))
    end

    it "reaps every pool child, including the crashed one" do
      crashrecoveryreport
      expect { Process.wait }.to(raise_error(Errno::ECHILD))
    end

    def sleeper
      lambda do |_slot|
        forked do |request, response|
          if (line = request.gets)
            id = JSON.parse(line)["id"]
            response.puts(JSON.generate(t: "start", id: id))
            response.puts(JSON.generate(t: "result", id: id, status: "killed", ms: 1, fails: []))
            response.flush
          end
          sleep(30)
          exit!(0)
        end
      end
    end

    def dormant
      harness(adapter, spawner: sleeper, hard_timeout: 0.3).run(ids: [ids.first])
    end

    it "reaps an idle worker without fabricating a nil result", :aggregate_failures do
      report = dormant
      expect(report.to_a.size).to(eq(1))
      expect(report.to_a.first.mutant_id).to(eq(ids.first))
      expect(report.to_a.first.status).to(eq(:killed))
    end

    def wedged
      lambda do |_slot|
        forked do |request, response|
          fork { sleep(6) }
          if (line = request.gets)
            response.puts(JSON.generate(t: "start", id: JSON.parse(line)["id"]))
            response.flush
          end
          sleep(30)
          exit!(0)
        end
      end
    end

    def deadline
      h = harness(adapter, spawner: wedged, hard_timeout: 0.3)

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      [h.run(ids: [ids.first]), Process.clock_gettime(Process::CLOCK_MONOTONIC) - started]
    end

    it "removes a wedged worker at the deadline, not when its pipe finally closes", :aggregate_failures do
      report, elapsed = deadline
      expect(report.to_a.map(&:status)).to(eq([:timeout]))
      expect(elapsed).to(be < 3.0)
    end
  end
end
