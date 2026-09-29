# frozen_string_literal: true

require "fileutils"
require "json"
require "kimera/execution/harness"
require "kimera/frameworks/adapter"
require "kimera/registry/builder"
require "tmpdir"

RSpec::Matchers.define_negated_matcher(:not_output, :output)

RSpec.describe(Kimera::Execution::Harness) do
  let(:registry) do
    Kimera::RegistryScan.new.source(<<~RUBY, file: "calc.rb")
      def a(x, y)
        x > y
      end
    RUBY
  end
  let(:ids) { registry.each.map { |m, _p| m.id } }

  # Running a test touches the mutant ids it covers, like a synthesized guard.
  def adapter(coverage: {}, failing: [], message: nil)
    Class.new(Kimera::Frameworks::Adapter) do
      define_method(:initialize) do
        @coverage = coverage
        @failing = failing
      end
      def source(_files) = self
      def test_ids = @coverage.keys
      define_method(:run) do |test_ids|
        test_ids.each { |t| Array(@coverage[t]).each { |mid| Kimera::Runtime.active?(mid) } }
        failed = test_ids & @failing
        Kimera::Frameworks::RunOutcome.new(
          passed: failed.empty?, failed_ids: failed,
          failures: failed.to_h { |t| [t, message || "assertion failed in #{t}"] }
        )
      end
    end.new
  end

  def harness(adapter, **)
    described_class.new(registry: registry, adapter: adapter, **)
  end

  def reloader(
    adapter, catalog: registry, isolation: Kimera::Execution::Isolation.new, root: "."
  )
    Kimera::Execution::Reload.new(registry: catalog, adapter: adapter, isolation: isolation, root: root)
  end

  # Re-selects the outer mutant before reporting, like a suite that manages
  # the runtime selector itself (Kimera's own does).
  def reselecting(coverage: {}, failing: [])
    outer = Kimera::Runtime.active
    Class.new(Kimera::Frameworks::Adapter) do
      define_method(:initialize) do
        @coverage = coverage
        @failing = failing
      end
      def source(_files) = self
      def test_ids = @coverage.keys
      define_method(:run) do |test_ids|
        Kimera::Runtime.active = outer
        test_ids.each { |t| Array(@coverage[t]).each { |mid| Kimera::Runtime.active?(mid) } }
        failed = test_ids & @failing
        Kimera::Frameworks::RunOutcome.new(passed: failed.empty?, failed_ids: failed)
      end
    end.new
  end

  # A forked run cannot append to the caller's +pids+.
  def processes(pids)
    Class.new(Kimera::Frameworks::Adapter) do
      def source(_files) = self
      def test_ids = ["t1"]
      define_method(:run) do |_ids|
        pids << Process.pid
        Kimera::Frameworks::RunOutcome.new(passed: true, failed_ids: [])
      end
    end.new
  end

  # The reload path deselects before entering the isolation block.
  def reselection
    outer = Kimera::Runtime.active
    Class.new(Kimera::Execution::Isolation) do
      define_method(:around) do |&block|
        Kimera::Runtime.active = outer
        block.call
      end
    end.new
  end

  def responder(status:, extra: nil)
    lambda do |_slot|
      forked do |request, response|
        while (line = request.gets)
          id = JSON.parse(line)["id"]
          response.puts(JSON.generate(t: "start", id: id))
          response.puts(JSON.generate(t: "result", id: id, status: status, ms: 1, fails: []))
          response.puts(JSON.generate(t: "leak", id: id, detail: extra)) if extra
          response.puts(JSON.generate(t: "ready"))
          response.flush
        end
        response.puts(JSON.generate(t: "done"))
        response.close
        exit!(0)
      end
    end
  end

  after { Kimera::Runtime.reset! }

  # Progress double that records events instead of drawing.
  def journal
    Class.new do
      attr_reader :events

      def initialize = @events = []
      def start(total, label = "mutants") = @events << [:start, total, label]
      def tick(status = nil) = @events << [:tick, status]
      def finish = @events << [:finish]
    end.new
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
      expect(h.coverage[ids.first]).to(contain_exactly("t1", "t2"))
      expect(h.coverage[ids.last]).to(contain_exactly("t2"))
    end

    it "raises BaselineFailure listing failing tests that cover an in-scope mutant" do
      h = harness(adapter(coverage: { "t1" => [], "t2" => [ids.first] }, failing: ["t2"]))
      expect { h.__send__(:measure!) }.to(raise_error(Kimera::Execution::BaselineFailure, /t2/))
    end

    # Failures that only show up in parallel depend on what shared the worker.
    it "names the worker that ran each failing test when the parallel baseline is red" do
      h = described_class.new(
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

    # A red baseline is often the suite's own order dependency, not the overlay.
    it "tells you how to reproduce the failure without kimera" do
      h = harness(adapter(coverage: { "t2" => [ids.first] }, failing: ["t2"]))
      expect { h.__send__(:measure!) }.to(raise_error(Kimera::Execution::BaselineFailure, /rspec t2 --order defined/))
    end

    it "asks the adapter for its framework's reproduce command, first ids only", :aggregate_failures do
      fake = adapter(coverage: { "t2" => [ids.first] }, failing: ["t2"])
      asked = []
      fake.define_singleton_method(:reproduce) { |shown| (asked << shown) && "ruby -n t2" }
      expect { harness(fake).__send__(:measure!) }
        .to(raise_error(Kimera::Execution::BaselineFailure, /reproduce without kimera: ruby -n t2\z/))
      expect(asked).to(eq([["t2"]]))
    end

    # The details and hint also name t2, so anchor on the summary text.
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
      long = "m" * (Kimera::Execution::BaselineFailure::MAX_MESSAGE + 50)
      h = harness(adapter(coverage: { "t2" => [ids.first] }, failing: ["t2"], message: long))
      error = failure(h)
      expect(error.message).to(include("#{"m" * Kimera::Execution::BaselineFailure::MAX_MESSAGE}…"))
      expect(error.message).not_to(include("m" * (Kimera::Execution::BaselineFailure::MAX_MESSAGE + 1)))
    end

    it "leaves an assertion message exactly at the limit untouched", :aggregate_failures do
      exact = "n" * Kimera::Execution::BaselineFailure::MAX_MESSAGE
      h = harness(adapter(coverage: { "t2" => [ids.first] }, failing: ["t2"], message: exact))
      error = failure(h)
      expect(error.message).to(include(exact))
      expect(error.message).not_to(include("…"))
    end

    # An unrelated red spec gates nothing, so it must not abort a scoped run.
    it "excludes a failing test that covers no in-scope mutant from the baseline", :aggregate_failures do
      h = harness(adapter(coverage: { "t1" => [ids.first], "t2" => [] }, failing: ["t2"]))
      expect { h.__send__(:measure!) }.not_to(raise_error)
      expect { h.__send__(:notice) }.to(output(/1 failing test.*excluded from the baseline/).to_stderr)
      expect(h.coverage[ids.first]).to(include("t1"))
    end

    it "names each excluded failing test with its failure, up to a limit", :aggregate_failures do
      failing = %w[t2 t3 t4 t5 t6 t7 t8]
      coverage = failing.to_h { |id| [id, []] }.merge("t1" => [ids.first])
      h = harness(adapter(coverage: coverage, failing: failing, message: "boom\nframe"))
      h.__send__(:measure!)
      expect { h.__send__(:notice) }.to(output(/excluded from the baseline .*:\n  t2: boom\n/).to_stderr)
      expect { h.__send__(:notice) }.to(output(/\n  t6: boom\n  … and 2 more\n\z/).to_stderr)
    end

    it "closes its own ledger afterward" do
      h = harness(adapter(coverage: { "t1" => [ids.first] }))
      expect { h.__send__(:measure!) }.not_to(change { Array(Kimera::Runtime.instance_variable_get(:@ledgers)).size })
    end

    # Suites may reset the selector in their own hooks (Kimera's do).
    # The ledger is handle-scoped, so touches from before the reset survive.
    def resetting
      Class.new(Kimera::Frameworks::Adapter) do
        def source(_files) = self
        def test_ids = %w[t_reset t_after]
        define_method(:run) do |test_ids|
          test_ids.each do |t|
            if t == "t_reset"
              Kimera::Runtime.active?(42)
              Kimera::Runtime.reset!
            end
            Kimera::Runtime.active?(99) if t == "t_after"
          end
          Kimera::Frameworks::RunOutcome.new(passed: true, failed_ids: [])
        end
      end.new
    end

    it "keeps coverage recorded by an example that resets the runtime", :aggregate_failures do
      h = harness(resetting)
      h.__send__(:measure!)
      expect(h.coverage[42]).to(contain_exactly("t_reset"))
      expect(h.coverage[99]).to(contain_exactly("t_after"))
    end

    # Kimera's own harness specs measure coverage inside the measured suite.
    def nested
      Class.new(Kimera::Frameworks::Adapter) do
        def source(_files) = self
        def test_ids = ["t_nested"]
        define_method(:run) do |_ids|
          inner = Kimera::Runtime.start!
          Kimera::Runtime.active?(7)
          Kimera::Runtime.drain!(inner)
          Kimera::Runtime.stop!(inner)
          Kimera::Frameworks::RunOutcome.new(passed: true, failed_ids: [])
        end
      end.new
    end

    it "keeps coverage for an example that runs its own nested measurement" do
      h = harness(nested)
      h.__send__(:measure!)
      expect(h.coverage[7]).to(contain_exactly("t_nested"))
    end

    # The loop deselects at the top of each iteration; the suite undoes that.
    it "keeps the loop's bookkeeping observable when the suite re-selects a mutant", :aggregate_failures do
      progress = journal
      h = harness(reselecting(coverage: { "t1" => [ids.first], "t2" => [] }), progress: progress)
      expect { h.__send__(:measure!) }.not_to(change { Array(Kimera::Runtime.instance_variable_get(:@ledgers)).size })
      expect(h.coverage[ids.first]).to(eq(["t1"]))
      expect(progress.events).to(eq([[:start, 2, "baseline"], [:tick, nil], [:tick, nil], [:finish]]))
    end

    it "still gates on a failing example when the suite re-selects a mutant" do
      h = harness(reselecting(coverage: { "t1" => [ids.first] }, failing: ["t1"]))
      expect { h.__send__(:measure!) }.to(raise_error(Kimera::Execution::BaselineFailure, /t1/))
    end

    def ticker
      Class.new do
        def start(_total, _label = nil); end

        def tick(_status = nil)
          Kimera::Runtime.active?(9_999_991)
          :ticked
        end

        def finish; end
      end.new
    end

    # The ticker touches a mutant between examples.
    it "discards touches recorded between examples" do
      h = harness(adapter(coverage: { "t1" => [], "t2" => [] }), progress: ticker)
      h.__send__(:measure!)
      expect(h.coverage).not_to(have_key(9_999_991))
    end

    # Serial in the parent so `quietly` can swallow suite writes.
    it "runs the baseline in this very process at jobs == 1" do
      pids = []
      h = harness(processes(pids))
      h.__send__(:measure!)
      expect(pids).to(eq([Process.pid]))
    end

    it "fans the baseline out to forked workers at jobs > 1" do
      pids = []
      h = described_class.new(registry: registry, adapter: processes(pids), jobs: 2)
      h.__send__(:measure!)
      expect(pids).to(be_empty) # children append to their own copy
    end

    def empty
      progress = journal
      h = harness(adapter(coverage: {}), progress: progress)
      before = Array(Kimera::Runtime.instance_variable_get(:@ledgers)).size

      expect { h.__send__(:measure!) }.not_to(raise_error)
      [before, Array(Kimera::Runtime.instance_variable_get(:@ledgers)).size, h.coverage, progress.events]
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
      expect(tally.failures).to(eq(["t1"]))
      expect(tally.irrelevant).to(be_empty)
    end

    it "routes a failing test touching no in-scope mutant to irrelevant", :aggregate_failures do
      tally = banked("t2", [])
      expect(tally.failures).to(be_empty)
      expect(tally.irrelevant).to(eq(["t2"]))
    end

    it "charges a lost parallel test and advances progress", :aggregate_failures do
      progress = journal
      lost = Kimera::Execution::BaselinePass.new(adapter: adapter, registry: registry, progress: progress)
      lost.__send__(:loss).call("t2", :crash)

      expect(lost.__send__(:tally).failures).to(eq(["t2"]))
      expect(progress.events).to(eq([[:tick, nil]]))
    end

    # A test lost with its worker is not a test failure; say which it was.
    it "explains why a lost parallel test counts as failed", :aggregate_failures do
      lost = Kimera::Execution::BaselinePass.new(adapter: adapter, registry: registry)
      lost.__send__(:loss).call("t1", :timeout, nil)
      lost.__send__(:relapse, "t1", :timeout)
      lost.__send__(:loss).call("t2", :crash, nil)
      messages = lost.instance_variable_get(:@messages)
      expect(messages["t1"]).to(
        eq(
          "its worker was killed at the hard timeout (--hard-timeout) before reporting a result, " \
            "and again when rerun alone"
        )
      )
      expect(messages["t2"]).to(eq("its worker died before reporting a result"))
    end
  end

  describe "#measure! parallel path (jobs > 1)" do
    def measurement(coverage)
      h = described_class.new(registry: registry, adapter: adapter(coverage: coverage), jobs: 2)
      h.__send__(:measure!)
      h.coverage
    end

    it "fans the coverage pass across the pool and matches the serial map", :aggregate_failures do
      coverage = measurement({ "t1" => [ids.first], "t2" => ids })
      expect(coverage[ids.first]).to(contain_exactly("t1", "t2"))
      expect(coverage[ids.last]).to(contain_exactly("t2"))
    end

    it "raises BaselineFailure when a forked example fails" do
      h = described_class.new(
        registry: registry, jobs: 2,
        adapter: adapter(coverage: { "t1" => [], "t2" => [ids.first] }, failing: ["t2"])
      )
      expect { h.__send__(:measure!) }.to(raise_error(Kimera::Execution::BaselineFailure, /t2/))
    end

    # Failures that only show up in parallel depend on what shared the worker.
    it "names the worker that ran each failing test when the parallel baseline is red" do
      h = described_class.new(
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
      Class.new(Kimera::Frameworks::Adapter) do
        def source(_files) = self
        def test_ids = ["t1"]
        define_method(:run) do |_ids|
          puts "SUITE NOISE out"

          warn "SUITE NOISE err"
          Kimera::Frameworks::RunOutcome.new(passed: true, failed_ids: [])
        end
      end.new
    end

    # At jobs == 1 the suite runs in this process, under the progress line.
    it "swallows suite writes to stdout/stderr during the serial baseline" do
      h = harness(noisy)
      expect { h.__send__(:measure!) }.to(not_output.to_stdout.and(not_output.to_stderr))
    end
  end

  describe "parallel coverage progress (jobs > 1)" do
    def parallel
      progress = journal
      described_class.new(
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
        described_class.new(registry: registry, adapter: adapter, progress: progress)
          .run(ids: [registry.each.first.first.id]),
        progress
      ]
    end

    it "reports class-body mutants as :isolated_only without evaluating them", :aggregate_failures do
      report, progress = body
      result = report.results.first
      expect(result.status).to(eq(:isolated_only))
      expect(result.detail).to(eq(Kimera::MutationPoint::CLASS_BODY_REASON))
      expect(progress.events).to(include(%i[tick isolated_only]))
    end

    it "neither gates nor drags the score", :aggregate_failures do
      report, = body
      expect(report.survived).to(be_empty)
      expect(report.score).to(eq(1.0))
      expect(report.summary).to(include("isolated_only=1"))
    end
  end

  describe "#load!" do
    it "eager-loads a detected Rails application before overlaying" do
      app = double("app")
      allow(app).to(receive(:eager_load!))
      stub_const("Rails", double("Rails", application: app))
      harness(adapter).__send__(:load!)
      expect(app).to(have_received(:eager_load!))
    end

    it "warns but continues when eager loading fails" do
      app = double("app")
      allow(app).to(receive(:eager_load!).and_raise(RuntimeError, "boom"))
      stub_const("Rails", double("Rails", application: app))
      expect { harness(adapter).__send__(:load!) }.to(output(/eager_load! failed \(RuntimeError: boom\)/).to_stderr)
    end

    it "is a no-op outside Rails" do
      # Probing a half-present Rails would warn, which is still wrong here.
      expect { harness(adapter).__send__(:load!) }.not_to(output.to_stderr)
    end

    it "skips an application that cannot eager-load, without warning" do
      stub_const("Rails", double("Rails", application: Object.new))
      expect { harness(adapter).__send__(:load!) }.not_to(output.to_stderr)
    end
  end

  describe "#warm! wiring" do
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
      Class.new(Kimera::Frameworks::Adapter) do
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
      described_class.new(registry: catalog(name), adapter: sink(seen), source_root: dir)
        .without_coverage!(["spec/a_spec.rb"])
      seen
    end

    it "hands the test files to the adapter" do
      stub_const("Warmwire", Class.new)
      expect(files("warmwire")).to(eq(["spec/a_spec.rb"]))
    end

    def red
      Class.new(Kimera::Frameworks::Adapter) do
        def source(_files) = self
        def test_ids = ["t1"]
        def run(_ids) = Kimera::Frameworks::RunOutcome.new(passed: false, failed_ids: ["t1"])
      end.new
    end

    it "raises BaselineFailure from the coverage-off baseline check too" do
      stub_const("Warmred", Class.new)
      registry = catalog("warmred")
      h = described_class.new(registry: registry, adapter: red, source_root: dir)
      expect { h.without_coverage!(["t1"]) }.to(raise_error(Kimera::Execution::BaselineFailure, /t1/))
    end

    def green(mods = nil)
      Class.new(Kimera::Frameworks::Adapter) do
        def source(_files) = self
        def test_ids = []
        def run(_ids) = Kimera::Frameworks::RunOutcome.new(passed: true, failed_ids: [])
        class_exec(&mods) if mods
      end.new
    end

    def starts
      proc do
        attr_reader(:booted)

        def start = @booted = true
      end
    end

    # Otherwise deleting the start call from warm! survives mutation.
    it "fires the adapter's suite-level setup hook during warm-up" do
      stub_const("Warmsuite", Class.new)
      registry = catalog("warmsuite")
      ad = green(starts)
      described_class.new(registry: registry, adapter: ad, source_root: dir).without_coverage!(["t1"])
      expect(ad.booted).to(be(true))
    end

    def active(id)
      Class.new(Kimera::Frameworks::Adapter) do
        define_method(:initialize) { |mid| @id = mid }
        def source(_files) = self
        def test_ids = ["t1"]
        define_method(:run) do |test_ids|
          Kimera::Runtime.active?(@id) if test_ids.any?
          Kimera::Frameworks::RunOutcome.new(passed: true, failed_ids: [])
        end
      end.new(id)
    end

    def default(name)
      registry = catalog(name)
      mid = registry.each.map { |m, _p| m.id }.first
      h = described_class.new(registry: registry, adapter: active(mid), source_root: dir)
      h.warm!(["t1"])
      [mid, h.coverage]
    end

    it "measures coverage by default when no flag is given" do
      stub_const("Warmdefault", Class.new)
      mid, coverage = default("warmdefault")
      expect(coverage[mid]).to(eq(["t1"]))
    end

    def rails
      app = double("app")
      allow(app).to(receive(:eager_load!))
      stub_const("Rails", double("Rails", application: app))
      app
    end

    it "eager-loads a detected Rails app during warm-up" do
      stub_const("Warmeager", Class.new)
      registry = catalog("warmeager")
      app = rails
      described_class.new(registry: registry, adapter: green, source_root: dir).without_coverage!(["t1"])
      expect(app).to(have_received(:eager_load!))
    end

    def database(name)
      stub_const("ActiveRecord::Base", Class.new)
      described_class.new(registry: catalog(name), adapter: green, source_root: dir, isolate_db: true)
    end

    it "wires DB isolation during warm-up when isolate_db is on" do
      stub_const("Warmiso", Class.new)
      h = database("warmiso")
      h.without_coverage!(["t1"])
      expect(h.__send__(:isolation)).to(be_a(Kimera::Execution::CompositeIsolation))
    end

    def first(registry) = registry.each.map { |m, _p| m.id }.first

    def ungated(name)
      registry = catalog(name)
      described_class.new(
        registry: registry, source_root: dir,
        adapter: adapter(coverage: { "t1" => [first(registry)], "t2" => [] }, failing: ["t2"])
      )
    end

    it "reports failing tests that gate nothing, after warm-up" do
      stub_const("Warmirr", Class.new)
      h = ungated("warmirr")
      expect { h.warm!(%w[t1 t2]) }.to(output(/1 failing test\(s\) cover no in-scope mutant/).to_stderr)
    end

    def quiet(name)
      registry = catalog(name)
      described_class.new(
        registry: registry, source_root: dir, adapter: adapter(coverage: { "t1" => [first(registry)] })
      )
    end

    it "stays silent after a fully green warm-up" do
      stub_const("Warmquiet", Class.new)
      h = quiet("warmquiet")
      expect { h.warm!(["t1"]) }.not_to(output.to_stderr)
    end
  end

  describe "#isolate!" do
    it "wraps isolation in a rolled-back transaction when isolate_db is on" do
      stub_const("ActiveRecord::Base", Class.new)
      h = harness(adapter, isolate_db: true)
      h.isolate!
      expect(h.__send__(:isolation)).to(be_a(Kimera::Execution::CompositeIsolation))
    end

    it "leaves isolation alone by default even with ActiveRecord loaded", :aggregate_failures do
      stub_const("ActiveRecord::Base", Class.new)
      h = harness(adapter)
      h.isolate!
      expect(h.__send__(:isolation)).to(be_a(Kimera::Execution::Isolation))
      expect(h.__send__(:isolation)).not_to(be_a(Kimera::Execution::CompositeIsolation))
    end

    it "stays a no-op when isolate_db is on but ActiveRecord is absent", :aggregate_failures do
      hide_const("ActiveRecord") if defined?(ActiveRecord)
      h = harness(adapter, isolate_db: true)
      expect { h.isolate! }.not_to(raise_error)
      expect(h.__send__(:isolation)).not_to(be_a(Kimera::Execution::CompositeIsolation))
    end
  end

  it "stays silent on stderr when no progress is injected" do
    expect do
      h = described_class.new(registry: registry, adapter: adapter(coverage: { "t1" => [] }))
      h.__send__(:measure!)
    end.not_to(output.to_stderr)
  end

  # Each warm child needs its own database, or workers deadlock on a shared one.
  describe "per-worker database isolation" do
    def database(jobs:, adapt: adapter)
      Kimera::Execution::ParallelTestDatabases.new(adapter: adapt, jobs: jobs)
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
      allow(db).to(receive(:active?).and_return(true))
      db.before_fork
      db.after_fork(3)
      [before, after]
    end

    it "runs the registered before/after fork hooks per worker when isolation is on", :aggregate_failures do
      before, after = callbacks
      expect(before).to(eq(1))
      expect(after).to(eq([3])) # slot index
    end

    # parallelize_teardown drops what parallelize_setup created; skipping it leaks databases.
    def drain
      cleaned = []
      parallelization(true)
      stub(after: ->(_i) {}, cleanup: ->(i) { cleaned << i })
      db = database(jobs: 2)
      db.before_exit(0)
      db.before_exit(nil) # injected spawners have no slot
      cleaned
    end

    # Rails hands parallelize_teardown the worker number, as it does parallelize_setup.
    it "runs the app's cleanup hooks with the worker's slot as it drains" do
      expect(drain).to(eq([0]))
    end

    it "empties the worker's database as it drains" do
      connection = double(tables: %w[users posts], adapter_name: "SQLite")
      allow(connection).to(receive(:truncate_tables))
      base = Class.new
      base.define_singleton_method(:connection) { connection }
      stub_const("ActiveRecord::Base", base)
      drain
      expect(connection).to(have_received(:truncate_tables).with("users", "posts"))
    end

    def scrub(adapter, truncate: nil)
      connection = double(tables: %w[users], adapter_name: adapter, execute: nil)
      truncation = allow(connection).to(receive(:truncate_tables))
      truncation.and_raise(truncate) if truncate
      stub_const("ActiveRecord::Base", Class.new)
      allow(ActiveRecord::Base).to(receive(:connection).and_return(connection))
      cleaned = []
      stub(cleanup: ->(index) { cleaned << index })
      errors = StringIO.new
      db = Kimera::Execution::ParallelTestDatabases.new(adapter: adapter, jobs: 2, errors: errors)
      allow(db).to(receive(:active?).and_return(true))
      db.before_exit(0)
      [connection, errors.string, cleaned]
    end

    # A thread left behind by a timed-out test can hold a table lock forever.
    it "bounds how long the teardown truncate waits for locks", :aggregate_failures do
      postgres, = scrub("PostgreSQL")
      mysql, = scrub("Mysql2")
      lite, = scrub("SQLite")

      expect(postgres).to(have_received(:execute).with("SET lock_timeout = '5s'").ordered)
      expect(postgres).to(have_received(:truncate_tables).with("users").ordered)
      expect(mysql).to(have_received(:execute).with("SET SESSION lock_wait_timeout = 5"))
      expect(lite).not_to(have_received(:execute))
    end

    it "warns and still runs the app's cleanup hooks when the teardown truncate gives up", :aggregate_failures do
      _, errors, cleaned = scrub("PostgreSQL", truncate: RuntimeError.new("lock timeout"))
      expect(errors).to(eq("kimera: could not empty the worker's test database (RuntimeError: lock timeout)\n"))
      expect(cleaned).to(eq([0]))
    end

    it "never runs a nil-slot worker's after-fork hook (injected/test spawners)" do
      stub(after: ->(_i) { raise(RuntimeError, "should not run") })
      db = database(jobs: 2)
      allow(db).to(receive(:active?).and_return(true))
      expect { db.after_fork(nil) }.not_to(raise_error)
    end

    it "turns on only for jobs > 1 with Rails parallel test databases enabled", :aggregate_failures do
      parallelization(true)
      stub(after: ->(_i) {})
      expect(database(jobs: 1).active?).to(be(false))
      expect(database(jobs: 2).active?).to(be(true))
    end

    # Only Minitest loads rails/test_help, which registers the hooks.
    # Trusting the flag alone would leave RSpec workers sharing one database.
    it "stays off when the app registered no fork hooks at all" do
      parallelization(true)
      stub(after: [])
      expect(database(jobs: 2).active?).to(be(false))
    end

    def registration
      parallelization(true)
      stub(after: [])
      stub_const("ActiveRecord::Base", Class.new)
      db = database(jobs: 2)
      allow(db).to(receive(:require).with("active_record/test_databases"))
      db.active?
      db
    end

    it "loads Rails' own hook registration before deciding" do
      expect(registration).to(have_received(:require).with("active_record/test_databases"))
    end

    def skip
      calls = []
      stub(after: ->(i) { calls << i })
      database(jobs: 2).after_fork(3)
      calls
    end

    it "skips the after-fork hooks entirely when isolation is off" do
      expect(skip).to(be_empty)
    end

    # The before-fork hook drops the shared DB socket. Rails runs it once,
    # ahead of the fleet: rerunning it per spawn (a replacement worker, say)
    # would run the app's hook while its siblings are mid-test.
    def forking
      before = []
      parallelization(true)
      stub(before: -> { before << :before }, after: ->(_i) {})
      driver = described_class.new(registry: registry, adapter: adapter, jobs: 2).__send__(:driver)
      pid, request, response = driver.worker(0)
      request.close
      response.read
      response.close
      Process.wait(pid)
      [before.dup, fleet(driver, before)]
    end

    def fleet(driver, before)
      driver.drive([], driver.method(:worker), resolve: ->(_m) {}, lost: ->(_i, _r) {})
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

    # Rails' own worker sets it before parallelize_setup; apps key per-worker
    # Redis dbs, lease namespaces and ports on it.
    it "sets ActiveSupport::TestCase.parallel_worker_id to the slot in a parallel worker", :aggregate_failures do
      expect(worker_id(2)).to(eq(4))
      expect(worker_id(1)).to(be_nil)
    end

    # Without its slot index, a child loses its own test database.
    def slot
      parallelization(true)
      reader, writer = IO.pipe
      stub(before: -> {}, after: ->(i) { writer.puts(i) })
      described_class.new(
        registry: registry, jobs: 2, soft_timeout: nil,
        adapter: adapter(coverage: { "t1" => [ids.first] })
      ).run(ids: [ids.first])
      writer.close
      result = reader.read

      reader.close
      result
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

    def starting
      Class.new(Kimera::Frameworks::Adapter) do
        attr_reader :booted

        def source(_files) = self
        def start = @booted = true
        def test_ids = []
        def run(_ids) = Kimera::Frameworks::RunOutcome.new(passed: true, failed_ids: [])
      end.new
    end

    def replay
      stub(after: ->(_i) {})
      ad = starting
      db = database(jobs: 2, adapt: ad)
      allow(db).to(receive(:active?).and_return(true))
      db.after_fork(1)
      ad.booted
    end

    it "replays the adapter's suite-level setup in the freshly forked worker" do
      expect(replay).to(be(true))
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
    it "passes silently when the suite is green" do
      h = harness(adapter(coverage: { "t1" => [] }))
      expect { h.__send__(:verify!) }.not_to(raise_error)
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
      Class.new(Kimera::Frameworks::Adapter) do
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

    # No stray blank line from an empty details block.
    it "renders exactly the summary and hint when no assertion messages exist" do
      expect(error.message).to(eq(message))
    end
  end

  describe "Verdicts#safe?" do
    it "is true for an ordinary point and for an unknown id", :aggregate_failures do
      verdicts = Kimera::Execution::Verdicts.new(registry)
      expect(verdicts.safe?(ids.first)).to(be(true))
      expect(verdicts.safe?(999_999)).to(be(true))
    end

    it "is false for a memoized (schema-unsafe) point" do
      memo = Kimera::RegistryScan.new.source(<<~RUBY, file: "m.rb")
        def total(a, b)
          @t ||= compute(a > b)
        end
      RUBY
      unsafe = memo.each.first.first.id
      expect(Kimera::Execution::Verdicts.new(memo).safe?(unsafe)).to(be(false))
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

    # nil means the deadline hit; a torn line means SIGKILL mid-write.
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

    it "returns nil from parse on malformed JSON" do
      expect(harness(adapter).__send__(:parse, "not json")).to(be_nil)
    end
  end

  # On Kimera's own runner a warm error is a self-crash, and a warm survivor
  # is unfalsifiable: a mutant that disables the runner passes every test.
  describe "Verdicts#reclassify!" do
    def result(id, status, file)
      Kimera::MutantResult.new(mutant_id: id, status: status, file: file, duration: 0.0)
    end

    let(:results) do
      {
        1 => result(1, :error, "lib/kimera/execution/shift.rb"),
        2 => result(2, :timeout, "lib/kimera/frameworks/rspec_adapter.rb"),
        3 => result(3, :killed, "lib/kimera/execution/shift.rb"),
        4 => result(4, :error, "app/models/user.rb"),
        5 => result(5, :survived, "lib/kimera/execution/shift.rb"),
        6 => result(6, :survived, "app/models/user.rb")
      }
    end

    before { Kimera::Execution::Verdicts.new(registry).reclassify!(results) }

    it "downgrades a runner error/timeout to isolated_only", :aggregate_failures do
      expect(results[1].status).to(eq(:isolated_only))
      expect(results[2].status).to(eq(:isolated_only))
    end

    it "leaves a genuine runner kill and ordinary-file verdicts alone", :aggregate_failures do
      expect(results[3].status).to(eq(:killed))
      expect(results[4].status).to(eq(:error))
      expect(results[6].status).to(eq(:survived))
    end

    it "downgrades an unfalsifiable warm survivor on the runner to isolated_only" do
      expect(results[5].status).to(eq(:isolated_only))
    end

    it "explains the downgrade: self-crash vs unfalsifiable survivor, with the original status", :aggregate_failures do
      expect(results[1].detail).to(include("--isolated"))
      expect(results[1].detail).to(include("self-crash"))
      expect(results[1].detail).to(include("warm error"))
      expect(results[5].detail).to(include("unfalsifiable"))
    end
  end

  describe(Kimera::Execution::Priority) do
    def order(coverage, ids) = described_class.new(coverage).order(ids)

    it "orders mutants heaviest-covering-first (longest runs start earliest)" do
      expect(order({ 1 => %w[a], 2 => %w[a b c], 3 => %w[a b] }, [1, 2, 3])).to(eq([2, 3, 1]))
    end

    it "counts covering tests by int key, then string key, else zero" do
      # 5 by integer key (2), 6 by string-key fallback (1), 8 unknown (0)
      expect(order({ 5 => %w[a b], "6" => %w[c] }, [8, 6, 5])).to(eq([5, 6, 8]))
    end

    it "treats every mutant as unit cost when no coverage map was built" do
      expect(order(nil, [5, 1, 3])).to(eq([5, 1, 3]))
    end
  end

  describe "Verdicts#reloadable?" do
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
      verdicts = Kimera::Execution::Verdicts.new(mixed_registry)
      body = mixed_registry.each.find { |_m, p| p.body? }.first.id
      method = mixed_registry.each.find { |_m, p| !p.body? }.first.id
      expect(verdicts.reloadable?(body)).to(be(false))
      expect(verdicts.reloadable?(method)).to(be(true))
    end

    it "treats an unknown id (no registry point) as reloadable" do
      expect(Kimera::Execution::Verdicts.new(registry).reloadable?(10_000_000)).to(be(true))
    end

    # Reload bakes the same source the overlay could not emit.
    it "is false for an unmutatable method-body point" do
      verdicts = Kimera::Execution::Verdicts.new(mixed_registry)
      mutant, point = mixed_registry.each.find { |_m, p| !p.body? }
      point.unmutatable!("unparser could not round-trip its guard")
      expect(verdicts.reloadable?(mutant.id)).to(be(false))
    end
  end

  describe "unmutatable mutants" do
    def unmutatable
      registry = Kimera::RegistryScan.new.source("def gt(a, b)\n  a > b\nend\n", file: "u.rb")
      registry.points.each { |point| point.unmutatable!("schemata setup failed (boom)") }
      progress = journal
      ids = registry.each.map { |mutant, _point| mutant.id }
      [described_class.new(registry: registry, adapter: adapter, progress: progress).run(ids: ids), progress]
    end

    it "reports them as :unmutatable, with the reason, without evaluating them", :aggregate_failures do
      report, progress = unmutatable
      expect(report.results.map(&:status).uniq).to(eq([:unmutatable]))
      expect(report.results.first.detail).to(eq("unmutatable: schemata setup failed (boom)"))
      expect(report.results.first.file).to(eq("u.rb"))
      expect(progress.events).to(include(%i[tick unmutatable]))
    end

    it "keeps them out of no_coverage and the score, but names them", :aggregate_failures do
      report, = unmutatable
      expect(report.uncovered).to(be_empty)
      expect(report.score).to(eq(1.0))
      expect(report.summary).to(include("unmutatable=2"))
    end
  end

  describe "#warm!" do
    let(:dir) { Dir.mktmpdir }

    after { FileUtils.remove_entry(dir) }

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
      Class.new(Kimera::Frameworks::Adapter) do
        define_method(:initialize) { |m| @mids = m }
        def source(_files) = self
        def test_ids = ["t1"]
        define_method(:run) do |_ids|
          @mids.each { |m| Kimera::Runtime.active?(m) }
          Kimera::Frameworks::RunOutcome.new(passed: true, failed_ids: [])
        end
      end.new(mids)
    end

    def mutants
      registry = fixture("WarmTarget")
      ids = registry.each.map { |m, _p| m.id }
      h = described_class.new(registry: registry, adapter: touching(ids), source_root: dir)
      [h.warm!(["t1"]), ids, h.coverage]
    end

    it "loads the suite, overlays schemata, and returns the live mutant ids", :aggregate_failures do
      stub_const("WarmTarget", Class.new)
      live, ids, coverage = mutants
      expect(live).to(match_array(ids))
      expect(coverage).not_to(be_empty)
    end

    def plain
      Class.new(Kimera::Frameworks::Adapter) do
        def source(_files) = self
        def test_ids = ["t1"]
        def run(_ids) = Kimera::Frameworks::RunOutcome.new(passed: true, failed_ids: [])
      end.new
    end

    it "runs the plain baseline check when coverage is disabled" do
      stub_const("WarmNoCov", Class.new)
      h = described_class.new(registry: fixture("WarmNoCov"), adapter: plain, source_root: dir)
      expect { h.without_coverage!(["t1"]) }.not_to(raise_error)
    end
  end

  describe "leak reporting in the scheduler" do
    it "records a leak message emitted by a pool worker" do
      spawner = responder(status: "killed", extra: "state leaked")
      report = harness(adapter, spawner: spawner).run(ids: ids)
      expect(report.leaks.map(&:detail)).to(include("state leaked"))
    end
  end

  describe "self-verdict reclassification in #run" do
    def survivor
      registry = Kimera::RegistryScan.new.source(<<~RUBY, file: "kimera/execution/shift.rb")
        def a(x, y)
          x > y
        end
      RUBY
      rid = registry.each.map { |m, _p| m.id }.first
      report =
        described_class.new(registry: registry, adapter: adapter, spawner: responder(status: "survived"))
          .run(ids: [rid])
      report.results.find { |r| r.mutant_id == rid }
    end

    it "downgrades a warm survivor on a harness-critical file", :aggregate_failures do
      result = survivor
      expect(result.status).to(eq(:isolated_only))
      expect(result.detail).to(include("unfalsifiable warm survivor"))
    end
  end

  # One schema-safe comparison and one memoized (schema-unsafe) one.
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

  # Kept fork-safe: pure Ruby, no shared IO.
  def observer(klass)
    Class.new(Kimera::Frameworks::Adapter) do
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
      h = described_class.new(
        registry: writing(dir, "HarnessE2E"), adapter: observer("HarnessE2E"),
        source_root: dir, soft_timeout: nil, leak_every: 0
      )
      h.warm!(["t1"])
      h.run
    end

    it "warms up and kills the schema-safe mutants via a pool worker", :aggregate_failures do
      stub_const("HarnessE2E", Class.new)
      report = outcome
      expect(report.results).not_to(be_empty)
      expect(report.statuses(:error)).to(be_empty)
      expect(report.killed).not_to(be_empty)
    end
  end

  describe "#evaluate_reload (reload fallback child logic, run in-process)" do
    # An in-process errand: the tests it names, and ticks that go nowhere.
    def errand(id, tests = ["t1"])
      Kimera::Execution::Reload::Errand.new(id, tests, nil, nil).tap { |e| e.define_singleton_method(:tick) { true } }
    end

    let(:dir) { Dir.mktmpdir }

    after { FileUtils.remove_entry(dir) }

    # memo(1, 2) is true, so `< => >` must be killed unless the bake never
    # reached the reloaded code.
    def classification
      registry = writing(dir, "HarnessReload")
      # The constant must exist before the bake is overlaid.
      load(File.join(dir, "harnessreload.rb"))
      reloader(observer("HarnessReload"), catalog: registry, root: dir)
        .__send__(:evaluate, errand(registry.each.find { |m, p| !p.safe? && m.label == "< => >" }.first.id))
    end

    it "bakes the mutation, reloads, and classifies the outcome" do
      stub_const("HarnessReload", Class.new)
      status, = classification
      expect(status).to(eq(:killed))
    end

    it "re-runs only the reloaded method of a file that was already required", :aggregate_failures do
      stub_const("HarnessRequired", Class.new)
      writing(dir, "HarnessRequired")
      path = File.join(dir, "harnessrequired.rb")
      File.write(path, File.read(path).sub("class HarnessRequired\n", "\\0  @loads = (@loads || 0) + 1\n"))
      registry = Kimera::RegistryScan.new(root: dir).build([path])
      require(path)
      unsafe = registry.each.find { |m, p| !p.safe? && m.label == "< => >" }.first.id
      status, = reloader(observer("HarnessRequired"), catalog: registry, root: dir).__send__(:evaluate, errand(unsafe))
      expect(status).to(eq(:killed))
      expect(HarnessRequired.instance_variable_get(:@loads)).to(eq(1))
    end

    def reload(name)
      stub_const(name, Class.new)
      registry = writing(dir, name)
      load(File.join(dir, "#{name.downcase}.rb"))
      [registry, registry.each.map { |m, _p| m.id }.find { |id| !registry.index[id].safe? }]
    end

    def plain(passed:)
      Class.new(Kimera::Frameworks::Adapter) do
        define_method(:initialize) { @passed = passed }
        def source(_files) = self
        def test_ids = ["t1"]
        define_method(:run) do |_ids|
          Kimera::Frameworks::RunOutcome.new(passed: @passed, failed_ids: @passed ? [] : ["t1"])
        end
      end.new
    end

    it "classifies a green re-selecting suite as survived" do
      registry, unsafe = reload("HarnessReselGreen")
      runner = reloader(plain(passed: true), catalog: registry, root: dir, isolation: reselection)
      expect(runner.__send__(:evaluate, errand(unsafe))).to(eq([:survived, []]))
    end

    def counting(tests, failing, calls)
      Class.new(Kimera::Frameworks::Adapter) do
        define_method(:source) { |_files| self }
        define_method(:test_ids) { tests }
        define_method(:run) do |ids|
          calls << ids
          failed = ids & failing
          Kimera::Frameworks::RunOutcome.new(passed: failed.empty?, failed_ids: failed)
        end
      end.new
    end

    it "runs one test at a time and stops at the first failure", :aggregate_failures do
      registry, unsafe = reload("HarnessReloadFast")
      calls = []
      runner = reloader(counting(%w[t1 t2 t3], ["t2"], calls), catalog: registry, root: dir, isolation: reselection)
      expect(runner.__send__(:evaluate, errand(unsafe, %w[t1 t2 t3]))).to(eq([:killed, ["t2"]]))
      expect(calls).to(eq([["t1"], ["t2"]]))
    end

    it "ticks the errand before every test it runs" do
      registry, unsafe = reload("HarnessReloadTick")
      spy = instance_spy(Kimera::Execution::Reload::Errand, id: unsafe, tests: %w[t1 t2 t3])
      runner = reloader(counting(%w[t1 t2 t3], [], []), catalog: registry, root: dir, isolation: reselection)
      runner.__send__(:evaluate, spy)
      expect(spy).to(have_received(:tick).exactly(3).times)
    end

    it "orders tests covering the mutant's method, then its file, before the rest" do
      registry, unsafe = reload("HarnessReloadOrder")
      point = registry.index[unsafe]
      other = registry.at(point.file).find { |p| p.method_name != point.method_name }
      kinship = Kimera::Execution::Kinship.new(registry, { other.ids.first => ["t4"], point.ids.first => %w[t3 t9] })
      expect(kinship.order(unsafe, %w[t1 t2 t3 t4])).to(eq(%w[t3 t4 t1 t2]))
    end

    it "keeps the suite order for an unknown mutant or missing coverage", :aggregate_failures do
      registry, unsafe = reload("HarnessReloadAlone")
      expect(Kimera::Execution::Kinship.new(registry, nil).order(unsafe, %w[t2 t1])).to(eq(%w[t2 t1]))
      expect(Kimera::Execution::Kinship.new(registry, {}).order(10_000_000, %w[t2 t1])).to(eq(%w[t2 t1]))
    end

    it "classifies a failing re-selecting suite as killed with its failures" do
      registry, unsafe = reload("HarnessReselRed")
      runner = reloader(plain(passed: false), catalog: registry, root: dir, isolation: reselection)
      expect(runner.__send__(:evaluate, errand(unsafe))).to(eq([:killed, ["t1"]]))
    end

    def cold
      registry, unsafe = reload("HarnessReloadCold")
      progress = journal
      [
        described_class.new(
          registry: registry, adapter: plain(passed: true),
          source_root: dir, soft_timeout: nil, progress: progress
        ).run(ids: [unsafe]),
        progress
      ]
    end

    it "runs the reload path end-to-end without a prior warm-up", :aggregate_failures do
      report, progress = cold
      expect(report.results.first.status).to(eq(:survived))
      expect(progress.events).to(include(%i[tick survived]))
    end

    # The reload child reports the reason; an :error would count as killed.
    it "reports a mutant unparser can't bake as unmutatable, with the reason", :aggregate_failures do
      allow(Kimera::Unparse).to(receive(:unparse).and_raise(KeyError, "key not found: :lvar"))
      report, progress = cold
      result = report.results.first
      expect(result.status).to(eq(:unmutatable))
      expect(result.detail).to(eq("unmutatable: unparser could not write its bake (KeyError: key not found: :lvar)"))
      expect(progress.events).to(include(%i[tick unmutatable]))
    end

    def boom
      Class.new(Kimera::Frameworks::Adapter) do
        def source(_files) = self
        def test_ids = ["t1"]
        def run(_ids) = raise(RuntimeError, "kaboom")
      end.new
    end

    def evaluation
      stub_const("HarnessBoom", Class.new)
      registry = writing(dir, "HarnessBoom")
      load(File.join(dir, "harnessboom.rb"))
      reloader(boom, catalog: registry, root: dir, isolation: reselection)
        .__send__(:evaluate, errand(registry.each.map { |m, _p| m.id }.find { |id| !registry.index[id].safe? }))
    end

    it "captures an exception during reload as an :error result", :aggregate_failures do
      status, detail = evaluation
      expect(status).to(eq(:error))
      expect(detail.first).to(include("RuntimeError: kaboom"))
    end

    it "classifies a bake unparser can't write as unmutatable, with the reason" do
      allow(Kimera::Unparse).to(receive(:unparse).and_raise(KeyError, "key not found: :lvar"))
      expect(evaluation).to(
        eq([:unmutatable, [], "unmutatable: unparser could not write its bake (KeyError: key not found: :lvar)"])
      )
    end
  end

  describe "#run_reload hard-deadline" do
    let(:dir) { Dir.mktmpdir }

    after { FileUtils.remove_entry(dir) }

    def hanging
      Class.new(Kimera::Frameworks::Adapter) do
        def source(_files) = self
        def test_ids = ["t1"]
        def run(_ids) = sleep(30)
      end.new
    end

    def crashing
      Class.new(Kimera::Frameworks::Adapter) do
        def source(_files) = self
        def test_ids = ["t1"]
        def run(_ids) = exit!(1)
      end.new
    end

    def timing(name, adapt, deadline:)
      stub_const(name, Class.new)
      registry = writing(dir, name)
      load(File.join(dir, "#{name.downcase}.rb"))
      unsafe = registry.each.map { |m, _p| m.id }.find { |id| !registry.index[id].safe? }

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      [
        reloader(adapt, catalog: registry, root: dir).run(unsafe, deadline: deadline),
        Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      ]
    end

    # Without the SIGKILL, reaping blocks until the child's sleep ends.
    it "hard-kills a reload child whose test overruns the deadline, as a timeout", :aggregate_failures do
      result, elapsed = timing("HarnessHang", hanging, deadline: 0.3)
      expect(result.status).to(eq(:timeout))
      expect(elapsed).to(be < 5)
    end

    def sluggish(tests, pause)
      Class.new(Kimera::Frameworks::Adapter) do
        define_method(:source) { |_files| self }
        define_method(:test_ids) { tests }
        define_method(:run) do |_ids|
          sleep(pause)
          Kimera::Frameworks::RunOutcome.new(passed: true, failed_ids: [])
        end
      end.new
    end

    # The deadline bounds one test: a suite longer than it is still judged.
    it "restarts the deadline for every test the reload child runs", :aggregate_failures do
      result, elapsed = timing("HarnessSlow", sluggish(%w[t1 t2 t3 t4], 0.2), deadline: 0.5)
      expect(result.status).to(eq(:survived))
      expect(elapsed).to(be > 0.5)
    end

    # EOF only arrives if the parent closed its own copy of the write end.
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
      h = described_class.new(
        registry: registry, adapter: observer("HarnessUnsafe"),
        source_root: dir, soft_timeout: nil, leak_every: 0,
        progress: progress
      )
      h.warm!(["t1"])
      unsafe = registry.each.map { |m, _p| m.id }.find { |id| !registry.index[id].safe? }
      report = h.run(ids: [unsafe])
      [report.results.find { |r| r.mutant_id == unsafe }, progress]
    end

    it "routes the memoized mutant through the reload fallback", :aggregate_failures do
      result, = unsafe
      expect(result).not_to(be_nil)
      expect(result.status).to(satisfy { |status| %i[killed survived no_coverage].include?(status) })
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
      expect(report.killed.map(&:mutant_id)).to(match_array(ids))
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
      expect(report.killed.map(&:mutant_id)).to(match_array(ids))
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
      # Not overwritten by a later verdict.
      expect(report.results.map(&:status)).to(eq([:timeout]))
    end
  end

  describe "default spawner" do
    def unstubbed
      harness(adapter(coverage: { "t1" => [ids.first] }), soft_timeout: nil).run(ids: [ids.first])
    end

    def terminating
      Class.new(Kimera::Frameworks::Adapter) do
        def source(_files) = self
        def test_ids = ["t1"]

        def run(_ids)
          Process.kill("TERM", Process.pid)
          sleep(5)
        end
      end.new
    end

    it "reports the signal and exception that ended a real pool worker", :aggregate_failures do
      result = harness(terminating, soft_timeout: nil).run(ids: [ids.first]).results.first
      expect(result.status).to(eq(:harness_error))
      expect(result.detail).to(start_with("worker crashed before result: died on signal 15 (SIGTERM)\n"))
      expect(result.detail).to(include("\nSignalException: SIGTERM\n"))
      expect(result.detail).to(include("nothing trapped SIGTERM"))
    end

    it "forks a real serving pool worker when none is injected", :aggregate_failures do
      report = unstubbed
      expect(report.results.map(&:mutant_id)).to(eq([ids.first]))
      expect(report.results.first.status).to(eq(:survived))
      expect { Process.wait }.to(raise_error(Errno::ECHILD))
    end
  end

  describe "pool crash recovery" do
    # The first worker accepts its id and dies; replacements kill everything.
    def crash
      crashed = false
      lambda do |_slot|
        first = !crashed
        crashed = true
        forked do |request, response|
          if first
            request.gets
            response.puts(JSON.generate(t: "crash", detail: "Boom: from the worker"))
            response.flush
            exit!(3)
          else
            while (line = request.gets)
              id = JSON.parse(line)["id"]
              response.puts(JSON.generate(t: "start", id: id))
              response.puts(JSON.generate(t: "result", id: id, status: "killed", ms: 1, fails: []))
              response.puts(JSON.generate(t: "ready"))
              response.flush
            end
            response.puts(JSON.generate(t: "done"))
            response.close
          end
          exit!(0)
        end
      end
    end

    let(:crashrecoveryreport) { harness(adapter, spawner: crash, jobs: 1).run(ids: ids.first(2)) }
    let(:byid) { crashrecoveryreport.results.to_h { |r| [r.mutant_id, r.status] } }

    it "charges the crashed id as an error and lets the replacement worker kill the rest", :aggregate_failures do
      expect(byid[ids[0]]).to(eq(:harness_error))
      expect(byid[ids[1]]).to(eq(:killed))
      expect(crashrecoveryreport.results.size).to(eq(2))
    end

    it "says how the crashed worker died and what it raised" do
      detail = crashrecoveryreport.results.find { |r| r.mutant_id == ids[0] }.detail
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
          sleep(30) # never says "ready", never exits
          exit!(0)
        end
      end
    end

    def dormant
      harness(adapter, spawner: sleeper, hard_timeout: 0.3).run(ids: [ids.first])
    end

    it "reaps an idle worker without fabricating a nil result", :aggregate_failures do
      report = dormant
      expect(report.results.size).to(eq(1))
      expect(report.results.first.mutant_id).to(eq(ids.first))
      expect(report.results.first.status).to(eq(:killed))
    end

    # A mutated app may fork a grandchild that holds the result pipe open.
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
      expect(report.results.map(&:status)).to(eq([:timeout]))
      expect(elapsed).to(be < 3.0)
    end
  end
end
