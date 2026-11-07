# frozen_string_literal: true

require "json"
require "kimera/execution/isolated"
require "kimera/execution/test_filter"
require "kimera/registry/builder"
require "timeout"

using ResultFields
using PointFields

RSpec.describe(Kimera::Execution::IsolatedExecution) do
  let(:registry) do
    Kimera::RegistryScan.new.source(<<~RUBY, file: "calc.rb")
      def a(x, y)
        x > y
      end
    RUBY
  end

  def runner(**)
    described_class.new(registry: registry, root: ".", tests: ["t1"], **)
  end

  def test_invoke_private(object, method, *, **, &)
    object.__send__(method, *, **, &)
  end

  def test_all_ids
    registry.each.map { |m, _p| m.to_i }
  end

  def first
    registry.each.first.first.to_i
  end

  def test_source_fixture
    "def a(x, y)\n  x > y\nend\n"
  end

  def test_recording_bar(sink) = ProgressJournal.new(sink)

  def test_canned_runner(root:, **options, &verdict)
    options = { progress: test_recording_bar([]) }.merge(options)
    Class.new(described_class) do
      define_method(:evaluate) do |id, _bay|
        Kimera::MutantResult.new(
          mutant_id: id, status: (verdict ? yield(id) : :killed), file: "calc.rb",
          duration: 0.0
        )
      end
    end.new(registry: registry, root: root, tests: ["t1"], **options)
  end

  describe "#waitfor" do
    def watchdog(hard_timeout:, poll_interval: 0.05)
      Kimera::Execution::IsolatedWatchdog.new(hard_timeout, poll: poll_interval)
    end

    def looked(poll)
      pid = Process.spawn("sleep", "0.1", pgroup: true)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      status = watchdog(hard_timeout: 5.0, poll_interval: poll).waitfor(pid)
      [status, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started]
    end

    it "honors the polling boundary while a child is still running", :aggregate_failures do
      status, elapsed = looked(0.6)
      expect(status).to(be_success)
      expect(elapsed).to(be_between(0.6, 2.4))
    end

    it "returns the exit status of a child that finishes in time" do
      r = watchdog(hard_timeout: 5.0)
      pid = Process.spawn("true", pgroup: true)
      status = r.waitfor(pid)
      expect(status).to(be_success)
    end

    def test_wedged_wait(timeout)
      pid = Process.spawn("sleep", "30", pgroup: true)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      [
        watchdog(hard_timeout: timeout).waitfor(pid),
        Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, pid
      ]
    end

    it "hard-kills a wedged child group and returns :timeout", :aggregate_failures do
      status, elapsed, pid = test_wedged_wait(0.3)
      expect(status).to(eq(:timeout))
      expect(elapsed).to(be < 5.0)
      expect { Process.kill(0, pid) }.to(raise_error(Errno::ESRCH))
    end

    def beating(pulse, beats)
      script = "for _ in $(seq #{beats}); do printf . >> \"$0\"; sleep 0.15; done"
      pid = Process.spawn("sh", "-c", script, pulse, pgroup: true)
      watchdog(hard_timeout: 0.5, poll_interval: 0.01).waitfor(pid, pulse)
    end

    it "lets a child run past the hard timeout while each test starts within it" do
      Dir.mktmpdir { |dir| expect(beating(File.join(dir, "pulse"), 8)).to(be_success) }
    end

    it "kills what a child left running in its group once it exits", :aggregate_failures do
      witness = self.witness
      pid = Process.spawn("sh", "-c", "sleep 30 & exit 3", pgroup: true, out: witness.holder)
      expect(watchdog(hard_timeout: 5.0).waitfor(pid).exitstatus).to(eq(3))
      expect(witness.outlived?).to(be(false))
    end

    def interrupt_after(seconds)
      Thread.new(Thread.current) do |waiting|
        sleep(seconds)
        waiting.raise(Interrupt)
      end
    end

    it "takes a child's group down with it when kimera is interrupted", :aggregate_failures do
      pid = Process.spawn("sleep", "300", pgroup: true, out: File::NULL)
      interrupt_after(0.2)
      expect { Timeout.timeout(10) { watchdog(hard_timeout: 5.0).waitfor(pid) } }.to(raise_error(Interrupt))
      expect { Process.kill(0, pid) }.to(raise_error(Errno::ESRCH))
    end
  end

  describe "#verdict" do
    def timeout
      r = runner(hard_timeout: 0.3)
      r.__send__(:plan).define_singleton_method(:command) { |*, **| [{}, %w[sleep 30]] }
      Dir.mktmpdir do |mirror|
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        status = test_invoke_private(r, :verdict, Kimera::Execution::Bay.new(mirror), []).to_h[:status]
        [status, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started]
      end
    end

    it "times out a wedged suite child within the deadline", :aggregate_failures do
      verdict, elapsed = timeout
      expect(verdict).to(eq(:timeout))
      expect(elapsed).to(be < 5.0)
    end
  end

  describe "parallel evaluation (jobs > 1)" do
    let(:canned) do
      Class.new(described_class) do
        attr_reader :seen

        def evaluate(id, _bay)
          (@seen ||= Hash.new { |h, k| h[k] = [] })[Thread.current] << id
          sleep(0.01)
          Kimera::MutantResult.new(mutant_id: id, status: :killed, file: "calc.rb", duration: 0.0)
        end
      end
    end

    def parallel(jobs: 3)
      Dir.mktmpdir do |root|
        File.write(File.join(root, "calc.rb"), "def a(x, y) = x > y\n")
        progress = []
        r = canned.new(
          registry: registry, root: root, tests: ["t1"], jobs: jobs, progress: test_recording_bar(progress)
        )
        ids = test_all_ids
        [r.run(ids: ids), progress, ids, r]
      end
    end

    it "drains the whole queue across workers and reports every verdict once", :aggregate_failures do
      report, progress, ids, r = parallel
      expect(report.to_a.map(&:mutant_id)).to(match_array(ids))
      expect(progress.count { |e| e == %i[tick killed] }).to(eq(ids.size))
      expect(progress.last).to(eq([:finish]))
      expect(r.seen.values.flatten).to(match_array(ids))
    end
  end

  describe "#verify!" do
    def every = { first => %w[t3 t2 t1] }

    def test_baseline(outcome, progress: Kimera::Execution::NullProgress.new, ids: [first], coverage: every)
      seen = []
      seated = method(:seat)
      engine =
        Class.new(described_class) do
          define_method(:verdict) do |bay, tests, **|
            seen << [File.file?(File.join(seated.call(bay).first, "calc.rb")), tests]
            outcome
          end
        end
      Dir.mktmpdir do |root|
        File.write(File.join(root, "calc.rb"), "def a(x, y) = x > y\n")
        engine.new(registry: registry, root: root, tests: %w[t1 t2 t3], hard_timeout: 7, progress: progress, coverage:)
          .verify!(ids)
      end
      seen
    end

    it "runs only the tests the mutants it is given will run, in suite order", :aggregate_failures do
      green = Kimera::Execution::IsolatedOutcome.new(:survived)
      coverage = { first => %w[t3 t1], 999 => %w[t2] }
      expect(test_baseline(green, ids: [first, 999], coverage:)).to(eq([[true, %w[t1 t3]]]))
      expect(test_baseline(green, ids: [], coverage:)).to(eq([]))
    end

    it "runs the tests once in a fresh mirror and passes when they are green", :aggregate_failures do
      green = Kimera::Execution::IsolatedOutcome.new(:survived)
      seen = nil
      expect { seen = test_baseline(green) }.not_to(output.to_stderr)
      expect(seen).to(eq([[true, %w[t1 t2 t3]]]))
    end

    it "notes the phase on the progress output before it runs" do
      events = []
      test_baseline(Kimera::Execution::IsolatedOutcome.new(:survived), progress: test_recording_bar(events))
      expect(events).to(eq([[:note, "isolated baseline (unmutated mirror)"]]))
    end

    it "aborts with the reason and the mirror layout when the unmutated suite is red", :aggregate_failures do
      red = Kimera::Execution::IsolatedOutcome.new(:timeout, nil, "timed out after 7s without a test finishing")
      expect { test_baseline(red, progress: test_recording_bar([])) }.to(
        raise_error(Kimera::Execution::BaselineFailure) do |error|
          expect(error.message).to(
            include(
              "isolated baseline is not green",
              "timed out after 7s without a test finishing"
            )
          )
          expect(error.message).to(end_with(Kimera::Execution::MirrorLayout::HINT))
        end
      )
    end
  end

  describe "MirrorLayout#populate" do
    def test_mirror
      Dir.mktmpdir do |root|
        %w[lib node_modules tmp .git].each { |dir| FileUtils.mkdir_p(File.join(root, dir, "sub")) }
        File.write(File.join(root, "Gemfile"), "")
        Dir.mktmpdir do |mirror|
          Kimera::Execution::MirrorLayout.new(root, registry).populate(mirror)
          yield(root, mirror)
        end
      end
    end

    def contents(mirror)
      at = ->(*parts) { File.join(mirror, *parts) }
      {
        sub: File.directory?(at["lib", "sub"]), lib_linked: File.symlink?(at["lib"]),
        modules: File.readlink(at["node_modules"]), tmp: Dir.children(at["tmp"]),
        git: File.exist?(at[".git"]), gemfile: File.file?(at["Gemfile"])
      }
    end

    it "copies sources, links dependencies, empties scratch dirs and skips history" do
      test_mirror do |root, mirror|
        expect(contents(mirror)).to(
          eq(sub: true, lib_linked: false, modules: File.join(root, "node_modules"), tmp: [], git: false, gemfile: true)
        )
      end
    end

    def mirrors?(root, path)
      Dir.mktmpdir do |mirror|
        Kimera::Execution::MirrorLayout.new(root, registry).populate(mirror)
        File.exist?(File.join(mirror, path))
      end
    end

    it "does not turn a scratch file into a directory" do
      Dir.mktmpdir do |root|
        File.write(File.join(root, "log"), "")
        expect(mirrors?(root, "log")).to(be(false))
      end
    end
  end

  describe "#initialize" do
    it "clamps jobs to at least 1 and coerces via to_i", :aggregate_failures do
      expect(runner(jobs: 0).__send__(:jobs)).to(eq(1))
      expect(runner(jobs: 4).__send__(:jobs)).to(eq(4))
      expect(runner(jobs: "3").__send__(:jobs)).to(eq(3))
    end
  end

  describe "#run routing" do
    def routing(root, jobs)
      Class.new(described_class) do
        define_method(:path) { @path }
        define_method(:serially) do |_ids, _tick|
          @path = :serial
          []
        end
        define_method(:concurrently) do |_ids, _tick|
          @path = :parallel
          []
        end
      end.new(
        registry: registry, root: root, tests: ["t1"],
        jobs: jobs, progress: test_recording_bar([])
      )
    end

    def paths(root)
      ids = test_all_ids
      serial = routing(root, 1)
      serial.run(ids: ids)
      parallel = routing(root, 2)
      parallel.run(ids: ids)
      [serial.path, parallel.path]
    end

    it "routes jobs == 1 to serial and jobs > 1 to parallel", :aggregate_failures do
      Dir.mktmpdir do |root|
        serial, parallel = paths(root)
        expect(serial).to(eq(:serial))
        expect(parallel).to(eq(:parallel))
      end
    end

    def tracking(root, jobs: 1)
      File.write(File.join(root, "calc.rb"), "def a(x, y) = x > y\n")
      seen = []
      [
        Class.new(described_class) do
          define_method(:evaluate) do |id, _bay|
            seen << id
            Kimera::MutantResult.new(mutant_id: id, status: :killed, file: "calc.rb", duration: 0.0)
          end
        end.new(
          registry: registry, root: root, tests: ["t1"], jobs: jobs, progress: test_recording_bar([])
        ),
        seen
      ]
    end

    it "defaults to every registered mutant when none are given" do
      Dir.mktmpdir do |root|
        r, seen = tracking(root)
        r.run
        expect(seen).to(match_array(test_all_ids))
      end
    end

    it "runs exactly the given subset when ids is passed" do
      Dir.mktmpdir do |root|
        r, seen = tracking(root)
        r.run(ids: [first])
        expect(seen).to(eq([first]))
      end
    end
  end

  describe "#run serial path (jobs == 1)" do
    def records(root, events)
      File.write(File.join(root, "calc.rb"), "def a(x, y) = x > y\n")
      seen = []
      [
        Class.new(described_class) do
          define_method(:evaluate) do |id, _bay|
            seen << id
            Kimera::MutantResult.new(mutant_id: id, status: :survived, file: "calc.rb", duration: 0.0)
          end
        end.new(
          registry: registry, root: root, tests: ["t1"], jobs: 1, progress: test_recording_bar(events)
        ),
        seen
      ]
    end

    def serial
      Dir.mktmpdir do |root|
        events = []
        r, seen = records(root, events)
        ids = test_all_ids
        { report: r.run(ids: ids), seen: seen, events: events, ids: ids }
      end
    end

    let(:ordered) { serial }

    it "evaluates every id in order and wraps a RunReport", :aggregate_failures do
      expect(ordered[:report].to_a.map(&:mutant_id)).to(eq(ordered[:ids]))
      expect(ordered[:seen]).to(eq(ordered[:ids]))
    end

    it "ticks each verdict once and brackets the run with start/finish", :aggregate_failures do
      expect(ordered[:events].first).to(eq([:start, ordered[:ids].size, "mutants"]))
      expect(ordered[:events].count { |e| e == %i[tick survived] }).to(eq(ordered[:ids].size))
      expect(ordered[:events].last).to(eq([:finish]))
    end

    def unannounced(root)
      File.write(File.join(root, "calc.rb"), "def a(x, y) = x > y\n")
      test_canned_runner(root: root, jobs: 1, progress: Kimera::Execution::NullProgress.new)
    end

    it "prints nothing per verdict; progress alone reports the run" do
      Dir.mktmpdir do |root|
        expect { unannounced(root).run(ids: [first]) }.not_to(output.to_stderr)
      end
    end

    def test_verdict_pairs(jobs)
      Dir.mktmpdir do |root|
        File.write(File.join(root, "calc.rb"), "def a(x, y) = x > y\n")
        verdict = ->(id) { id.even? ? :killed : :survived }
        test_canned_runner(root: root, jobs: jobs, &verdict)
          .run(ids: test_all_ids).to_a.map { |r| [r.mutant_id, r.status] }.sort
      end
    end

    it "produces the same verdicts serially and in parallel" do
      expect(test_verdict_pairs(1)).to(eq(test_verdict_pairs(3)))
    end
  end

  describe "#evaluate" do
    it "returns an :error result for an unknown mutant id", :aggregate_failures do
      synth = Kimera::Overlay.new(registry)
      result = Dir.mktmpdir { |m| test_invoke_private(runner, :evaluate, 10_000_000, Kimera::Execution::Bay.new(m, nil, synth)) }
      expect(result.status).to(eq(:error))
      expect(result.detail).to(eq("unknown mutant"))
    end

    it "reports :no_coverage when no test exercises the mutant" do
      synth = Kimera::Overlay.new(registry)
      result = Dir.mktmpdir { |m| test_invoke_private(runner, :evaluate, first, Kimera::Execution::Bay.new(m, nil, synth)) }
      expect(result.status).to(eq(:no_coverage))
    end

    def test_paced(given)
      Class.new(described_class) do
        define_method(:verdict) do |_bay, locations, **|
          given.concat(locations)
          Kimera::Execution::IsolatedOutcome.new(:survived)
        end
      end
    end

    def paced = { coverage: { first => %w[slow fast] }, timings: { "fast" => 0.1, "slow" => 2.0 } }

    def paced_trial(given)
      Dir.mktmpdir do |root|
        File.write(File.join(root, "calc.rb"), test_source_fixture)
        test_mirrored(test_paced(given).new(registry: registry, root: root, tests: [], **paced), root, first).first
      end
    end

    it "hands the mutant's child its covering tests fastest first by baseline time" do
      given = []
      result = paced_trial(given)
      expect([given, result.covering_tests]).to(eq([%w[fast slow], %w[slow fast]]))
    end

    it "settles a mutant whose tests the screen drops, without staging or running it", :aggregate_failures do
      given = []
      registry.index.fetch(first).mark!(Kimera::Reason.revisit(Kimera::Reason::BOOT_REASON))
      r = test_paced(given).new(
        registry: registry, root: ".", tests: %w[t1],
        filter: Kimera::Execution::TestFilter.new(registry: registry, flaky: %w[t1])
      )
      result = test_invoke_private(r, :evaluate, first, Kimera::Execution::Bay.new("/nonexistent", nil, Kimera::Overlay.new(registry)))
      expect(
        [
          result.status, result.detail,
          given
        ]
      ).to(eq([:no_coverage, "covered only by flaky test(s), which never kill: t1", []]))
    end

    def test_mirrored(runner, root, id, synth = Kimera::Overlay.new(registry))
      Dir.mktmpdir do |mirror|
        FileUtils.cp_r(File.join(root, "calc.rb"), File.join(mirror, "calc.rb"))
        bay = Kimera::Execution::Bay.new(mirror, nil, synth)
        [test_invoke_private(runner, :evaluate, id, bay), File.read(File.join(mirror, "calc.rb"))]
      end
    end

    def test_baker(root, id, sink, pause, quality)
      readings = [10.0, 12.5]
      seated = method(:seat)
      Class.new(described_class) do
        define_method(:verdict) do |bay, _locations, first: false|
          sink << [File.read(File.join(seated.call(bay).first, "calc.rb")), first]
          sleep(pause) if pause
          Kimera::Execution::IsolatedOutcome.new(:killed, ["t1[1:1]"])
        end
        define_method(:now) { |*| readings.shift } unless pause
      end.new(registry: registry, root: root, tests: ["t1"], coverage: { id => ["t1"] }, **quality)
    end

    def test_baking_evaluate(id, pause: nil, quality: {}, synth: Kimera::Overlay.new(registry))
      baked = []
      Dir.mktmpdir do |root|
        File.write(File.join(root, "calc.rb"), test_source_fixture)
        runner = test_baker(root, id, baked, pause, quality)
        result, restored = test_mirrored(runner, root, id, synth)
        [result, baked.first, restored]
      end
    end

    it "bakes the mutant, takes the verdict, and restores the file afterward", :aggregate_failures do
      result, baked, restored = test_baking_evaluate(first)
      expect(result).to(have_fields(status: :killed, duration: 2.5, covering_tests: ["t1"], failing_tests: ["t1[1:1]"]))
      expect(baked.first).not_to(eq(test_source_fixture))
      expect(restored).to(eq(test_source_fixture))
    end

    it "asks the mutant's test child to stop at the first failure" do
      _result, (_source, first_failure), = test_baking_evaluate(first)
      expect(first_failure).to(be(true))
    end

    it "has the child run every covering test and records the failing ones as killers under test quality",
      :aggregate_failures do
      result, (_source, first_failure), = test_baking_evaluate(first, quality: { test_quality: true })
      expect([first_failure, result.killing_tests]).to(eq([false, ["t1[1:1]"]]))
      expect(test_baking_evaluate(first).first.killing_tests).to(be_nil)
    end

    it "times the verdict on the monotonic clock", :aggregate_failures do
      result, = test_baking_evaluate(first, pause: 0.05)
      expect(result.status).to(eq(:killed))
      expect(result.duration).to(be_between(0.05, 5.0))
    end

    def test_raising_evaluate(id)
      Dir.mktmpdir do |root|
        File.write(File.join(root, "calc.rb"), test_source_fixture)
        runner =
          Class.new(described_class) do
            define_method(:verdict) { |*| raise RuntimeError, "boom" }
          end.new(registry: registry, root: root, tests: ["t1"], coverage: { id => ["t1"] })
        test_mirrored(runner, root, id).first
      end
    end

    it "captures a verdict-time exception as an :error result", :aggregate_failures do
      result = test_raising_evaluate(first)
      expect(result.status).to(eq(:error))
      expect(result.detail).to(eq("RuntimeError: boom"))
    end

    def unwritable
      Class.new do
        def bake(*)
          raise(Kimera::Overlay::Unbakeable, "kimera could not write its bake (KeyError: key not found: :lvar)")
        end
      end.new
    end

    it "reports :unmutatable, with the reason, for a mutant kimera can't bake", :aggregate_failures do
      result, baked, restored = test_baking_evaluate(first, synth: unwritable)
      expect([result.status, result.file, result.covering_tests]).to(eq([:unmutatable, "calc.rb", ["t1"]]))
      expect(result.detail).to(eq("unmutatable: kimera could not write its bake (KeyError: key not found: :lvar)"))
      expect([baked, restored]).to(eq([nil, test_source_fixture]))
    end

    def unreadable(id)
      Dir.mktmpdir do |root|
        r = described_class.new(registry: registry, root: root, tests: ["t1"], coverage: { id => ["t1"] })
        Dir.mktmpdir do |mirror|
          File.write(File.join(mirror, "calc.rb"), "mirror copy\n")
          [
            test_invoke_private(r, :evaluate, id, Kimera::Execution::Bay.new(mirror, nil, Kimera::Overlay.new(registry))),
            File.read(File.join(mirror, "calc.rb"))
          ]
        end
      end
    end

    it "leaves the mirror copy untouched when the original cannot be read", :aggregate_failures do
      result, mirror = unreadable(first)
      expect(result.status).to(eq(:error))
      expect(result.detail).to(include("Errno::ENOENT"))
      expect(mirror).to(eq("mirror copy\n"))
    end
  end

  describe "#verdict (command stubbed on the runner)" do
    def command(invocation, asked: [], **)
      plan = Object.new
      plan.define_singleton_method(:command) do |_mirror, _locations, ledger, first:, **|
        asked << first
        [{}, invocation.respond_to?(:call) ? invocation.call(ledger) : invocation]
      end
      r = runner(**)
      r.instance_variable_set(:@_plan, plan)
      r
    end

    def bayed(mirror) = Kimera::Execution::Bay.new(mirror)

    def test_verdict_of(invocation, **)
      Dir.mktmpdir { |m| test_invoke_private(command(invocation, **), :verdict, Kimera::Execution::Bay.new(m), []) }
    end

    def test_ledger_child(failures, failing, code)
      json = { failures: failures, failing: failing }.to_json
      ->(ledger) { [Gem.ruby, "-e", "File.write(ARGV[0], #{json.dump}); exit #{code}", ledger] }
    end

    it "maps a child that exits without reporting to :harness_error, whatever its status", :aggregate_failures do
      expect(test_verdict_of(["true"]).to_h[:status]).to(eq(:harness_error))
      expect(test_verdict_of(["false"]).to_h[:status]).to(eq(:harness_error))
    end

    it "explains a silent crash with the tail of the child's stderr" do
      outcome = test_verdict_of([Gem.ruby, "-e", "warn 'boot failed: NameError'; exit 1"])
      expect(outcome.to_h[:detail]).to(eq("test child exited 1 without reporting results:\nboot failed: NameError"))
    end

    it "maps a child that overruns the hard deadline to :timeout" do
      expect(test_verdict_of(%w[sleep 30], hard_timeout: 0.3).to_h[:status]).to(eq(:timeout))
    end

    it "lets a test whose baseline outlasts the hard timeout run to its own limit", :aggregate_failures do
      slow = command(%w[sleep 0.6], hard_timeout: 0.3, timings: { "t" => 0.1 })
      outcome = Dir.mktmpdir { |m| test_invoke_private(slow, :verdict, Kimera::Execution::Bay.new(m), ["t"]) }
      expect(outcome.to_h[:status]).to(eq(:harness_error))
      expect(
        test_verdict_of(
          %w[sleep 30],
          hard_timeout: 0.3
        ).to_h[:detail]
      ).to(eq("timed out after 0.3s without a test finishing"))
    end

    it "kills on a reported failure and names the failing tests", :aggregate_failures do
      outcome = test_verdict_of(test_ledger_child(1, ["./spec/a_spec.rb[1:1]"], 1))
      expect(outcome.to_h[:status]).to(eq(:killed))
      expect(outcome.to_h[:failing_tests]).to(eq(["./spec/a_spec.rb[1:1]"]))
    end

    it "keeps a clean reported run that exits zero :survived" do
      expect(test_verdict_of(test_ledger_child(0, [], 0)).to_h[:status]).to(eq(:survived))
    end

    it "reports a non-zero exit with zero failures as :harness_error, not a kill", :aggregate_failures do
      outcome = test_verdict_of(test_ledger_child(0, [], 2))
      expect(outcome.to_h[:status]).to(eq(:harness_error))
      expect(outcome.to_h[:detail]).to(start_with("suite exited 2 with 0 failures"))
      expect(outcome.to_h[:failing_tests]).to(be_nil)
    end

    it "has only a mutant's run stop at the first failure" do
      asked = []
      runner = command(test_ledger_child(0, [], 0), asked: asked)
      ask = ->(mirror, asks) { test_invoke_private(runner, :verdict, bayed(mirror), [], **asks) }
      Dir.mktmpdir { |m| [{}, { first: true }].each { |asks| ask.call(m, asks) } }
      expect(asked).to(eq([false, true]))
    end

    it "hands the child a ledger path that does not exist yet" do
      script = "fresh = File.directory?(File.dirname(ARGV[0])) && !File.exist?(ARGV[0]); " \
        "File.write(ARGV[0], '{\"failures\":0}'); exit(fresh ? 0 : 1)"
      expect(test_verdict_of(->(ledger) { [Gem.ruby, "-e", script, ledger] }).to_h[:status]).to(eq(:survived))
    end
  end

  describe "#with_mirror" do
    def test_mirrored_contents
      Dir.mktmpdir do |root|
        File.write(File.join(root, "calc.rb"), "x = 1\n")
        FileUtils.mkdir_p(File.join(root, "lib"))
        File.write(File.join(root, "lib", "b.rb"), "y = 2\n")
        r = described_class.new(registry: registry, root: root, tests: ["t1"])
        captured = nil
        contents = nil
        test_invoke_private(r, :with_mirror) do |mirror|
          captured = mirror
          contents = [File.read(File.join(mirror, "calc.rb")), File.read(File.join(mirror, "lib", "b.rb"))]
        end
        [contents, captured]
      end
    end

    it "copies the project into a temp dir, yields it, and cleans up after", :aggregate_failures do
      contents, mirror = test_mirrored_contents
      expect(contents).to(eq(["x = 1\n", "y = 2\n"]))
      expect(Dir.exist?(mirror)).to(be(false))
    end
  end

  describe "result builders" do
    it "coerces a nil duration to 0.0 and carries the covering tests", :aggregate_failures do
      result =
        test_invoke_private(runner, :result, 5, "calc.rb", status: :survived, duration: nil, covering_tests: ["t1"])
      expect(result.status).to(eq(:survived))
      expect(result.duration).to(eq(0.0))
      expect(result.covering_tests).to(eq(["t1"]))
    end

    it "builds an :error result carrying the file and detail with zero duration", :aggregate_failures do
      result = test_invoke_private(runner, :error, 5, "calc.rb", "boom")
      expect(result).to(have_fields(status: :error, file: "calc.rb", detail: "boom", duration: 0.0))
    end
  end
end
