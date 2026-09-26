# frozen_string_literal: true

require "kimera/execution/isolated"
require "kimera/registry/builder"
require "kimera/report/progress"

# A mutant baked into the harness's own timeout code can wedge its suite,
# so the runner's watchdog is tested directly here.
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

  def test_invoke_private(object, method, *, &)
    object.__send__(method, *, &)
  end

  def test_all_ids
    registry.each.map { |m, _p| m.id }
  end

  def first
    registry.each.first.first.id
  end

  def test_source_fixture
    "def a(x, y)\n  x > y\nend\n"
  end

  # enabled? true suppresses trace's stderr lines.
  def test_recording_bar(sink)
    Class.new do
      define_method(:initialize) { |s| @s = s }
      def enabled? = true
      define_method(:start) { |total, label = "mutants"| @s << [:start, total, label] }
      define_method(:tick) { |status = nil| @s << [:tick, status] }
      define_method(:finish) { @s << [:finish] }
    end.new(sink)
  end

  def test_canned_runner(root:, **opts, &verdict)
    opts = { progress: test_recording_bar([]) }.merge(opts)
    Class.new(described_class) do
      define_method(:evaluate) do |trial|
        id = trial.id
        Kimera::MutantResult.new(
          mutant_id: id, status: (verdict ? yield(id) : :killed), file: "calc.rb",
          duration: 0.0
        )
      end
    end.new(registry: registry, root: root, tests: ["t1"], **opts)
  end

  describe "#waitfor" do
    it "honors the polling boundary while a child is still running", :aggregate_failures do
      r = runner(hard_timeout: 5.0, poll_interval: 0.0125)
      allow(Process).to(receive(:waitpid2).and_return([nil, nil]))
      allow(r).to(receive(:sleep))

      expect(test_invoke_private(r, :attempt, 123, Float::INFINITY)).to(eq(:continue))
      expect(r).to(have_received(:sleep).with(0.0125))
    end

    it "returns the exit status of a child that finishes in time" do
      r = runner(hard_timeout: 5.0)
      pid = Process.spawn("true", pgroup: true)
      status = test_invoke_private(r, :waitfor, pid)
      expect(status).to(be_success)
    end

    def test_wedged_wait(timeout)
      pid = Process.spawn("sleep", "30", pgroup: true)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      [
        test_invoke_private(runner(hard_timeout: timeout), :waitfor, pid),
        Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, pid
      ]
    end

    it "hard-kills a wedged child group and returns :timeout", :aggregate_failures do
      status, elapsed, pid = test_wedged_wait(0.3)
      expect(status).to(eq(:timeout))
      expect(elapsed).to(be < 5.0)
      # kill 0 probes for existence
      expect { Process.kill(0, pid) }.to(raise_error(Errno::ESRCH))
    end
  end

  describe "#verdict" do
    # Without its own process group, the group SIGKILL hits ESRCH and
    # waitpid blocks until the wedged child exits on its own.
    def timeout
      r = runner(hard_timeout: 0.3)
      allow(r.__send__(:plan)).to(receive(:command).and_return([{}, %w[sleep 30]]))
      Dir.mktmpdir do |mirror|
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        [test_invoke_private(r, :verdict, mirror, []), Process.clock_gettime(Process::CLOCK_MONOTONIC) - started]
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

        def evaluate(trial)
          (@seen ||= Hash.new { |h, k| h[k] = [] })[Thread.current] << trial.id
          sleep(0.01) # let other workers claim queue items
          Kimera::MutantResult.new(mutant_id: trial.id, status: :killed, file: "calc.rb", duration: 0.0)
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
      expect(report.results.map(&:mutant_id)).to(match_array(ids))
      expect(progress.count { |e| e == %i[tick killed] }).to(eq(ids.size))
      expect(progress.last).to(eq([:finish]))
      expect(r.seen.values.flatten).to(match_array(ids))
    end

    def silent(root, jobs: 2)
      File.write(File.join(root, "calc.rb"), "def a(x, y) = x > y\n")
      canned.new(registry: registry, root: root, tests: ["t1"], jobs: jobs, progress: Kimera::Execution::NullProgress)
    end

    it "emits stderr trace lines on the parallel path when the bar is off" do
      Dir.mktmpdir do |root|
        ids = test_all_ids
        expect { silent(root).run(ids: ids) }
          .to(output(%r{kimera: isolated #{ids.size}/#{ids.size}\s+#\d+ killed}).to_stderr)
      end
    end
  end

  describe "#trace" do
    def result(status)
      Kimera::MutantResult.new(mutant_id: 7, status: status, file: "calc.rb", duration: 1.25)
    end

    it "logs one verdict line to stderr when the progress bar is off" do
      expect { test_invoke_private(runner, :trace, result(:killed), 3, 10) }
        .to(output(%r{kimera: isolated 3/10\s+#7 killed\s+calc\.rb\s+\(1\.2s\)}).to_stderr)
    end

    it "stays quiet when the interactive bar is rendering" do
      bar = Kimera::Report::Progress.new(io: StringIO.new, enabled: true)
      r = runner(progress: bar)
      expect { test_invoke_private(r, :trace, result(:survived), 1, 2) }.not_to(output.to_stderr)
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
        define_method(:serially) do |_ids|
          @path = :serial
          []
        end
        define_method(:concurrently) do |_ids|
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
          define_method(:evaluate) do |trial|
            seen << trial.id
            Kimera::MutantResult.new(mutant_id: trial.id, status: :killed, file: "calc.rb", duration: 0.0)
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
          define_method(:evaluate) do |trial|
            seen << trial.id
            Kimera::MutantResult.new(mutant_id: trial.id, status: :survived, file: "calc.rb", duration: 0.0)
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
      expect(ordered[:report].results.map(&:mutant_id)).to(eq(ordered[:ids]))
      expect(ordered[:seen]).to(eq(ordered[:ids]))
    end

    it "ticks each verdict once and brackets the run with start/finish", :aggregate_failures do
      expect(ordered[:events].first).to(eq([:start, ordered[:ids].size, "mutants"]))
      expect(ordered[:events].count { |e| e == %i[tick survived] }).to(eq(ordered[:ids].size))
      expect(ordered[:events].last).to(eq([:finish]))
    end

    def trace(root)
      File.write(File.join(root, "calc.rb"), "def a(x, y) = x > y\n")
      test_canned_runner(root: root, jobs: 1, progress: Kimera::Execution::NullProgress)
    end

    it "emits a stderr trace line per verdict when the bar is off" do
      Dir.mktmpdir do |root|
        expect { trace(root).run(ids: [first]) }
          .to(output(%r{kimera: isolated 1/1\s+##{first} killed\s+calc\.rb}).to_stderr)
      end
    end

    def test_verdict_pairs(jobs)
      Dir.mktmpdir do |root|
        File.write(File.join(root, "calc.rb"), "def a(x, y) = x > y\n")
        verdict = ->(id) { id.even? ? :killed : :survived }
        test_canned_runner(root: root, jobs: jobs, &verdict)
          .run(ids: test_all_ids).results.map { |r| [r.mutant_id, r.status] }.sort
      end
    end

    it "produces the same verdicts serially and in parallel" do
      expect(test_verdict_pairs(1)).to(eq(test_verdict_pairs(3)))
    end
  end

  describe "#evaluate" do
    it "returns an :error result for an unknown mutant id", :aggregate_failures do
      result = Dir.mktmpdir { |m| test_invoke_private(runner, :evaluate, Kimera::Execution::Trial.new(10_000_000, m, Kimera::Overlay.new(registry))) }
      expect(result.status).to(eq(:error))
      expect(result.detail).to(eq("unknown mutant"))
    end

    it "reports :no_coverage when no test exercises the mutant" do
      # Default coverage is empty, so the plan yields no tests.
      result = Dir.mktmpdir { |m| test_invoke_private(runner, :evaluate, Kimera::Execution::Trial.new(first, m, Kimera::Overlay.new(registry))) }
      expect(result.status).to(eq(:no_coverage))
    end

    def test_baking_evaluate(id)
      baked = nil
      Dir.mktmpdir do |root|
        File.write(File.join(root, "calc.rb"), test_source_fixture)
        r =
          Class.new(described_class) do
            define_method(:verdict) do |mirror, _locs|
              baked = File.read(File.join(mirror, "calc.rb"))
              :killed
            end
          end.new(registry: registry, root: root, tests: ["t1"], coverage: { id => ["t1"] })
        allow(r).to(receive(:now).and_return(10.0, 12.5))
        Dir.mktmpdir do |mirror|
          FileUtils.cp_r(File.join(root, "calc.rb"), File.join(mirror, "calc.rb"))
          [
            test_invoke_private(r, :evaluate, Kimera::Execution::Trial.new(id, mirror, Kimera::Overlay.new(registry))),
            baked,
            File.read(File.join(mirror, "calc.rb"))
          ]
        end
      end
    end

    it "bakes the mutant, takes the verdict, and restores the file afterward", :aggregate_failures do
      result, baked, restored = test_baking_evaluate(first)
      expect(result.status).to(eq(:killed))
      expect(result.duration).to(eq(2.5))
      expect(result.covering_tests).to(eq(["t1"]))
      expect(baked).not_to(eq(test_source_fixture))
      expect(restored).to(eq(test_source_fixture))
    end

    def test_raising_evaluate(id)
      Dir.mktmpdir do |root|
        File.write(File.join(root, "calc.rb"), test_source_fixture)
        r =
          Class.new(described_class) do
            define_method(:verdict) { |*| raise RuntimeError, "boom" }
          end.new(registry: registry, root: root, tests: ["t1"], coverage: { id => ["t1"] })
        Dir.mktmpdir do |mirror|
          FileUtils.cp_r(File.join(root, "calc.rb"), File.join(mirror, "calc.rb"))
          test_invoke_private(r, :evaluate, Kimera::Execution::Trial.new(id, mirror, Kimera::Overlay.new(registry)))
        end
      end
    end

    it "captures a verdict-time exception as an :error result", :aggregate_failures do
      result = test_raising_evaluate(first)
      expect(result.status).to(eq(:error))
      # The class tells the operator what blew up, not just what it said.
      expect(result.detail).to(eq("RuntimeError: boom"))
    end

    def unreadable(id)
      Dir.mktmpdir do |root|
        r = described_class.new(registry: registry, root: root, tests: ["t1"], coverage: { id => ["t1"] })
        Dir.mktmpdir do |mirror|
          File.write(File.join(mirror, "calc.rb"), "mirror copy\n")
          [
            test_invoke_private(r, :evaluate, Kimera::Execution::Trial.new(id, mirror, Kimera::Overlay.new(registry))),
            File.read(File.join(mirror, "calc.rb"))
          ]
        end
      end
    end

    it "leaves the mirror copy untouched when the original cannot be read", :aggregate_failures do
      # No calc.rb under root, so there is no original to restore from.
      result, mirror = unreadable(first)
      expect(result.status).to(eq(:error))
      expect(result.detail).to(include("Errno::ENOENT"))
      expect(mirror).to(eq("mirror copy\n"))
    end
  end

  describe "#verdict (command stubbed on the runner)" do
    # verdict only consumes the plan's command, so no real bake is needed.
    def command(cmd, **)
      plan = Object.new
      plan.define_singleton_method(:command) { |_mirror, _locations| [{}, cmd] }
      r = runner(**)
      r.instance_variable_set(:@_plan, plan)
      r
    end

    it "maps a zero-exit child to :survived" do
      r = command(["true"])
      Dir.mktmpdir { |m| expect(test_invoke_private(r, :verdict, m, [])).to(eq(:survived)) }
    end

    it "maps a non-zero-exit child to :killed" do
      r = command(["false"])
      Dir.mktmpdir { |m| expect(test_invoke_private(r, :verdict, m, [])).to(eq(:killed)) }
    end

    it "maps a child that overruns the hard deadline to :timeout" do
      r = command(%w[sleep 30], hard_timeout: 0.3)
      Dir.mktmpdir { |m| expect(test_invoke_private(r, :verdict, m, [])).to(eq(:timeout)) }
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
      trial = Kimera::Execution::Trial.new(5, nil, nil, "calc.rb")
      result = test_invoke_private(runner, :result, trial, :survived, nil, ["t1"])
      expect(result.status).to(eq(:survived))
      expect(result.duration).to(eq(0.0))
      expect(result.covering_tests).to(eq(["t1"]))
    end

    it "builds an :error result carrying the file and detail with zero duration", :aggregate_failures do
      trial = Kimera::Execution::Trial.new(5, nil, nil, "calc.rb")
      result = test_invoke_private(runner, :error, trial, "boom")
      expect(result.status).to(eq(:error))
      expect(result.file).to(eq("calc.rb"))
      expect(result.detail).to(eq("boom"))
      expect(result.duration).to(eq(0.0))
    end
  end
end
