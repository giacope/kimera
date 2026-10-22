# frozen_string_literal: true

require "json"
require "open3"
require "fileutils"
require "kimera/cli"
require "kimera/cli/baseline"
require "kimera/cli/mutant"
require "kimera/cli/run"
require "kimera/cli/survivors"
require "kimera/cli/workflows"
require "kimera/report/actions"
require "kimera/report/formats"
require "kimera/report/tally"
require "kimera/report/text"
require "kimera/scope/config"
require "stringio"
require "tmpdir"

RSpec.describe Kimera::CLI, :aggregate_failures do
  let(:dir) { Dir.mktmpdir }
  let(:out) { StringIO.new }
  let(:errors) { StringIO.new }

  after { FileUtils.remove_entry(dir) }

  def result(id, status, **attributes)
    Kimera::MutantResult.new(mutant_id: id, status: status, file: "app/x.rb", duration: 0.0, **attributes)
  end

  def report(*results)
    Kimera::RunReport.new(results: results)
  end

  def written(document)
    File.join(dir, "report.json").tap { |path| File.write(path, JSON.generate(document)) }
  end

  def fixture(row) = written("results" => [row])

  def project(files)
    files.each do |path, body|
      FileUtils.mkdir_p(File.dirname(File.join(dir, path)))
      File.write(File.join(dir, path), body)
    end
  end

  def directories(*names) = FileUtils.mkdir_p(names.map { |name| File.join(dir, name) })

  def without(variable)
    original = ENV.delete(variable)
    yield
  ensure
    ENV[variable] = original if original
  end

  def machine(rows)
    run = instance_double(
      Kimera::RunReport,
      document: {
        "schema_version" => 1, "counts" => { total: 4 }, "mutation_score" => 0.0,
        "results" => rows, "leaks" => [{ "mutant_id" => 1, "detail" => "leak" }], "run" => { "jobs" => 2 }
      }
    )
    outputs = Array.new(3) { StringIO.new }
    %w[github sarif ndjson].zip(outputs).each do |format, output|
      Kimera::Report::Formats.new(io: output).emit(format, run, metadata: { "jobs" => 2 })
    end
    outputs
  end

  describe "command dispatch" do
    let(:standalone) do
      <<~RUBY
        require "kimera/cli"
        report = ARGV.fetch(0)
        abort("report failed") unless Kimera::CLI.new.run(["report", report]).zero?
        abort("mutant failed") unless Kimera::CLI.new.run(["mutant", "1", "--report", report]).zero?
      RUBY
    end

    def lazy
      [Kimera::CLI::Survivors, Kimera::CLI::Mutant].each do |handler|
        allow(handler).to(receive(:new).and_return(instance_double(handler, run: 0)))
      end
      described_class.new(io: out, errors: errors).tap { |cli| allow(cli).to(receive(:require_relative)) }
    end

    it "requires the lazy report and mutant handlers before dispatching" do
      cli = lazy
      cli.__send__(:report, ["report.json"])
      cli.__send__(:mutant, ["1", "--report", "report.json"])
      expect(cli).to(have_received(:require_relative).with("cli/survivors"))
      expect(cli).to(have_received(:require_relative).with("cli/mutant"))
    end

    it "suggests a command exactly three edits away" do
      expect(Kimera::CLI::Suggestion.new(["run"]).hint("rxxx")).to(eq('; did you mean "run"?'))
      expect(described_class.new(io: out, errors: errors).run(["rxxx"])).to(eq(1))
      expect(errors.string).to(include('did you mean "run"?'))
    end

    it "suggests nothing for a distant one" do
      described_class.new(io: out, errors: errors).run(["completely-unknown"])
      expect(errors.string).not_to(include("did you mean"))
    end

    it "loads report and mutant handlers when the base CLI is loaded alone" do
      path = fixture("mutant_id" => 1, "status" => "survived", "file" => "x.rb", "label" => "x", "original" => "x")
      output, status = Open3.capture2e(Gem.ruby, "-I", File.expand_path("../../lib", __dir__), "-e", standalone, path)
      expect(status).to(be_success, output)
      expect(output).to(include("1 survived mutant(s):", "#1  survived"))
    end
  end

  describe "baseline validation" do
    def target = File.join(dir, "baseline.yml")

    def source = fixture("mutant_id" => 9, "status" => "survived", "file" => "x.rb", "line" => 2, "label" => "x")

    def baseline(argv)
      [Dir.chdir(dir) { Kimera::CLI::Baseline.new(io: out, errors: errors).run(argv) }, out.string, errors.string]
    end

    it "rejects every invalid create input" do
      expect(baseline(%w[create --reason why])[2]).to(include("no such report: tmp/kimera/report.json"))
      expect(baseline(["create", source])[2]).to(include("requires --reason"))
      expect(baseline(["create", "missing.json", "--reason", "why"])[2]).to(include("no such report"))
    end

    it "creates a baseline and refuses to replace it implicitly" do
      status, output, = baseline(["create", source, "--reason", "why", "--output", target])
      expect(status).to(eq(0))
      expect(output).to(include("Created #{target} with 1 accepted survivor(s).", "baseline: #{target}"))
      expect(baseline(["create", source, "--reason", "why", "--output", target])[2]).to(include("already exists"))
    end

    it "rejects incomplete reports" do
      bad = fixture("mutant_id" => 1, "status" => "survived", "file" => "x.rb")
      expect(baseline(["create", bad, "--reason", "why", "--output", target])[2])
        .to(include("report is missing line for mutant #1"))
    end

    it "rejects invalid review invocations" do
      expect(baseline(["review"])[2]).to(include("Usage: kimera baseline review BASELINE.yml"))
      expect(baseline(["review", "missing.yml"])[2]).to(include("no such baseline"))
    end
  end

  describe "mutant reruns" do
    def rerun(settings)
      row = { "file" => "app/x.rb", "key" => "app/x.rb:1:0123abcd" }
      Kimera::CLI::Mutant.new.__send__(:arguments_for, row, settings)
    end

    def mutant(*argv) = Kimera::CLI::Mutant.new(io: out, errors: errors).run(argv)

    it "requires a mutant ID" do
      expect(mutant).to(eq(1))
      expect(errors.string).to(include("mutant ID is required"))
    end

    it "requires a report" do
      expect(Dir.chdir(dir) { mutant("7") }).to(eq(1))
      expect(errors.string).to(include("no such report: tmp/kimera/report.json (run kimera run first"))
    end

    it "preserves coverage and isolation provenance" do
      arguments = rerun(
        "framework" => "minitest", "source_root" => "src", "tests" => ["test/a_test.rb"],
        "operators" => ["comparison"], "coverage" => false, "isolated" => true
      )
      expect(arguments).to(include("--no-coverage", "--isolated", "--framework", "minitest", "--source-root", "src"))
      expect(arguments.first(3)).to(eq(["app/x.rb", "--focus", "app/x.rb:1:0123abcd"]))
    end

    it "asks for a fresh report when the rerun row predates mutant keys" do
      path = written("run" => {}, "results" => [{ "mutant_id" => 7, "file" => "x.rb" }])
      expect(mutant("7", "--report", path, "--rerun")).to(eq(1))
      expect(errors.string)
        .to(eq("kimera: report has no mutant keys; regenerate it with kimera run --report, then rerun\n"))
      expect(out.string).to(be_empty)
    end

    {
      "no mutant #7" => [], "has no source file" => [{ "mutant_id" => 7 }],
      "has no run provenance" => [{ "mutant_id" => 7, "file" => "x.rb" }]
    }.each do |message, rows|
      it "rejects a report whose mutant row says: #{message}" do
        expect(mutant("7", "--report", written("results" => rows), "--rerun")).to(eq(1))
        expect(errors.string).to(include(message))
      end
    end
  end

  describe "run argument, cycle, and digest boundaries" do
    let(:tiny) { Kimera::RegistryScan.new.source("def x; 1; end\n", file: "x.rb") }
    let(:digest) { instance_double(Kimera::CLI::Run::Digest, emit: nil) }

    def options
      {
        report: nil, json: nil, format: "text", fail_on_no_coverage: false, quiet: false, log: nil,
        framework: "rspec", source_root: ".", tests: [], exclude_tests: [], operators: [],
        coverage: true, isolated: false, jobs: 1
      }
    end

    def concluded(settings, gate: 0)
      alerts = instance_double(Kimera::CLI::Run::Alerts, gate: gate)
      loaded = instance_double(Kimera::Incremental::Session, report: report)
      cycle = Kimera::CLI::Run::Cycle.new(settings, tiny, digest: digest, alerts: alerts)
      [cycle.__send__(:conclude, [], [], loaded), alerts]
    end

    def emission(coverage)
      { coverage: coverage, path: nil, format: "text", metadata: anything, log: nil, scope: nil, summary: nil }
    end

    it "rejects an invalid output format before running" do
      expect { Kimera::CLI::Run::Arguments.new.parse(["--format", "xml"]) }
        .to(
          raise_error(
            Kimera::UsageError,
            'unknown report format "xml" (choose: text, json, ndjson, github, sarif, markdown)'
          )
        )
    end

    it "sends machine formats to the output stream and text formats to the narration stream" do
      output = StringIO.new
      emission = Kimera::CLI::Run::Emission.new(io: out, output: output)
      emission.emit(report, tiny, format: "json", metadata: { "framework" => "rspec" })
      expect(out.string).to(eq(""))
      expect(JSON.parse(output.string).fetch("run")).to(eq("framework" => "rspec"))
    end

    it "chooses the error stream for a machine format" do
      cli = Kimera::CLI::Run.new(io: out, errors: errors)
      expect(cli.__send__(:digest, format: "json").instance_variable_get(:@io)).to(equal(errors))
    end

    it "gates by default, and hints at uncovered mutants" do
      status, alerts = concluded(options, gate: 7)
      expect(status).to(eq(7))
      expect(alerts).to(have_received(:gate))
      expect(digest).to(have_received(:emit).with(anything, tiny, **emission(:hint)))
    end

    it "lists uncovered mutants under fail_on_no_coverage" do
      concluded(options.merge(fail_on_no_coverage: true))
      expect(digest).to(have_received(:emit).with(anything, tiny, **emission(:list)))
    end

    it "lists and scores uncovered mutants under count_no_coverage" do
      concluded(options.merge(count_no_coverage: true))
      expect(digest).to(have_received(:emit).with(anything, tiny, **emission(:list))) do |emitted, *|
        expect(emitted.counted).to(eq([:no_coverage]))
      end
    end

    it "records count_no_coverage in the report metadata" do
      concluded(options.merge(count_no_coverage: true))
      recorded = hash_including(metadata: hash_including("count_no_coverage" => true))
      expect(digest).to(have_received(:emit).with(anything, anything, recorded))
    end

    it "neither lists nor scores them without count_no_coverage" do
      concluded(options.merge(count_no_coverage: false))
      uncounted = satisfy { |emitted| emitted.counted.empty? }
      expect(digest).to(have_received(:emit).with(uncounted, tiny, **emission(:hint)))
    end

    def emitted(name, **settings)
      path = File.join(dir, name)
      Kimera::CLI::Run::Emission.new(io: StringIO.new).emit(report, tiny, path: path, **settings)
      JSON.parse(File.read(path))
    end

    it "writes report metadata only when supplied" do
      expect(emitted("plain.json")).not_to(have_key("run"))
      expect(emitted("annotated.json", metadata: { "jobs" => 2 }).fetch("run")).to(eq("jobs" => 2))
    end

    it "respects color overrides, and leaves color off where no terminal is" do
      expect(Kimera::CLI::Run::Emission.new(color: false).__send__(:color?)).to(be(false))
      expect(Kimera::CLI::Run::Emission.new(color: true).__send__(:color?)).to(be(true))
      without("NO_COLOR") { expect(Kimera::CLI::Run::Emission.new(io: StringIO.new).__send__(:color?)).to(be(false)) }
    end

    it "records verbose paths and tests, including empty lists" do
      Kimera::CLI::Run::Digest.new(io: out, emission: nil).verbose(
        framework: "rspec", jobs: 1, paths: ["app/**/*.rb"],
        tests: ["spec/x_spec.rb"], format: "text"
      )
      expect(out.string).to(include("sources=app/**/*.rb tests=spec/x_spec.rb format=text"))
    end

    describe "the gate and provenance" do
      def base = options.merge(tests: ["spec/**/*_spec.rb"], operators: ["comparison"])

      it "never calls the gate when it is off" do
        status, alerts = concluded(base.merge(gate: false), gate: 9)
        expect(status).to(eq(0))
        expect(alerts).not_to(have_received(:gate))
      end

      it "returns the gate's status when it is on" do
        expect(concluded(base.merge(gate: true), gate: 9).first).to(eq(9))
      end

      it "records complete provenance" do
        cycle = Kimera::CLI::Run::Cycle.new(base.merge(gate: true), tiny, digest: digest)
        expect(cycle.__send__(:provenance)).to(
          eq(
            "framework" => "rspec", "source_root" => ".", "tests" => ["spec/**/*_spec.rb"],
            "exclude_tests" => [], "operators" => ["comparison"], "coverage" => true,
            "isolated" => false, "jobs" => 1, "narrowed" => false,
            "judge_isolated_only" => false, "confirm_survivors" => false
          )
        )
      end
    end

    def called(settings)
      verbose = instance_double(Kimera::CLI::Run::Digest, verbose: nil)
      cycle = Kimera::CLI::Run::Cycle.new(settings, tiny, digest: verbose)
      allow(cycle).to(receive(:scope))
      cycle.call
      verbose
    end

    it "runs verbose setup only when requested" do
      expect(called(verbose: false)).not_to(have_received(:verbose))
      expect(called(verbose: true)).to(have_received(:verbose).with(verbose: true))
    end

    def focused(settings, ids, registry = tiny)
      Kimera::CLI::Run::Cycle.new(settings, registry, digest: nil).__send__(:focus, ids)
    end

    it "validates focused IDs" do
      expect(focused({ verbose: true }, [1, 2])).to(eq([1, 2]))
      expect(focused({ focus: [1] }, [1, 2])).to(eq([1]))
      expect { focused({ focus: [3] }, [1, 2]) }.to(raise_error(Kimera::UsageError, /3/))
    end

    describe "focus by key" do
      def keyed = Kimera::RegistryScan.new.source("def x(a)\n  a > 1\nend\n", file: "x.rb")

      it "focuses by ordinal or key" do
        key = keyed.keys[1]
        expect(key).to(start_with("x.rb:2:"))
        expect(focused({ focus: [key, "2"] }, [1, 2, 3], keyed)).to(eq([1, 2]))
      end

      it "follows a key whose line moved, and rejects an unknown key" do
        expect(focused({ focus: [keyed.keys[1].sub(":2:", ":7:")] }, [1, 2, 3], keyed)).to(eq([1]))
        expect { focused({ focus: ["x.rb:2:ffffffff", "3"] }, [1, 2, 3], keyed) }
          .to(raise_error(Kimera::UsageError, "focused mutant(s) not in scope: x.rb:2:ffffffff"))
      end
    end

    def harnessed(settings, env)
      allow(Kimera::CLI::Run::Pass).to(receive(:new).and_return(instance_double(Kimera::CLI::Run::Pass, call: nil)))
      Kimera::CLI::Run::Cycle.new(settings, tiny, digest: nil).__send__(:harness, [1], env: env)
    end

    # `.rspec`'s `--require spec_helper` loads the helper while the adapter is
    # built, so a coverage floor gated on KIMERA must see it before then.
    it "sets KIMERA before loading the framework adapter" do
      env = {}
      seen = nil
      allow(Kimera::Frameworks::SUITES).to(receive(:load) { seen = env["KIMERA"] })
      harnessed({ framework: "rspec" }, env)
      expect(seen).to(eq("1"))
    end

    # Workers forked later, and the adapter as it loads the suite, read the run's seed from there.
    it "exports the run's seed to the environment before loading the adapter, and clears a stale one" do
      seen = []
      env = { "KIMERA_SEED" => "3" }
      allow(Kimera::Frameworks::SUITES).to(receive(:load) { seen << env["KIMERA_SEED"] })
      [{ framework: "rspec", seed: 42 }, { framework: "rspec" }].each { |settings| harnessed(settings, env) }
      expect([seen, env.key?("KIMERA_SEED")]).to(eq([["42", nil], false]))
    end

    # The adapter, doctor and isolated children read load_path: from there.
    it "exports the configured load path to the environment before loading the adapter" do
      seen = []
      env = {}
      allow(Kimera::Frameworks::SUITES).to(receive(:load) { seen << env["KIMERA_LOAD_PATH"] })
      [{ framework: "rspec", load_path: %w[support test/helpers] }, { framework: "rspec" }]
        .each { |settings| harnessed(settings, env) }
      expect(seen).to(eq(["support#{File::PATH_SEPARATOR}test/helpers", ""]))
    end
  end

  describe "workflow branches" do
    def initialized(*argv) = Kimera::CLI::Init.new(io: out, errors: errors, root: dir).run(argv)

    def doctored(*argv) = Kimera::CLI::Doctor.new(io: out, errors: errors, root: dir).run(argv)

    it "initializes a minitest project under --dry-run, writing nothing" do
      directories("test") && project("thing.rb" => "class Thing; end\n")
      expect(initialized("--dry-run")).to(eq(0))
      expect(out.string).to(include("framework: minitest", "paths:", "lib/**/*.rb", "count_no_coverage: true"))
      expect(YAML.safe_load(out.string).fetch("tests")).to(eq(["test/**/*_test.rb"]))
      expect(File).not_to(exist(File.join(dir, ".kimera.yml")))
    end

    it "rejects an unknown init option" do
      expect(initialized("--bogus")).to(eq(1))
    end

    it "detects RSpec when both test directories exist and names the chosen framework" do
      directories("test", "spec", "app") && project("app/x.rb" => "class X; end\n")
      expect(initialized).to(eq(0))
      expect(out.string).to(eq("Created .kimera.yml for rspec.\nNext: kimera doctor\n"))
      expect(YAML.safe_load_file(File.join(dir, ".kimera.yml")).fetch("tests")).to(eq(["spec/**/*_spec.rb"]))
    end

    it "reports broken doctor checks" do
      expect(doctored).to(eq(1))
      expect(out.string).to(
        include(
          "Configuration: none found", "Source scope: no Ruby files",
          "Test discovery: no test files", "not a repository", "no Rails-specific"
        )
      )
      expect(errors.string).to(include("doctor found 2 blocking issue(s)"))
    end

    it "reports healthy doctor checks" do
      directories(".git")
      project("app/x.rb" => "class X; end\n", "spec/x_spec.rb" => "# spec\n", "config/application.rb" => "# rails\n")
      project(".kimera.yml" => "framework: rspec\npaths: [app/**/*.rb]\ntests: [spec/**/*_spec.rb]\n")
      expect(doctored).to(eq(0))
      expect(out.string)
        .to(include("Configuration: .kimera.yml (rspec)", "Git: incremental runs are available", "Rails detected"))
    end

    it "fails when a test file cannot load, and accepts a worktree's .git file" do
      project("spec/x_spec.rb" => "# spec\n", ".git" => "gitdir: /elsewhere\n")
      failure = instance_double(Process::Status, success?: false)
      allow(Kimera::Execution::SUITE).to(receive(:call).and_return(["x_spec.rb:1: boom (RuntimeError)\n", failure]))
      expect(doctored).to(eq(1))
      expect(out.string).to(include("✗ Test loading: x_spec.rb:1: boom (RuntimeError)", "✓ Git: incremental"))
    end

    describe "doctor's baseline check" do
      let(:doctor) do
        project("spec/x_spec.rb" => "# spec\n")
        green = instance_double(Process::Status, success?: true)
        allow(Kimera::Execution::SUITE).to(receive(:call).and_return(["", green]))
        Kimera::CLI::Doctor.new(io: out, errors: errors, root: dir).tap do |doctor|
          allow(doctor).to(receive(:baselines).and_return([["✓", "Baseline: configured test suite is green"]]))
        end
      end

      it "is skipped unless requested" do
        expect(doctor.run([])).to(eq(1))
        expect(doctor).not_to(have_received(:baselines))
      end

      it "runs under --check-baseline" do
        expect(doctor.run(["--check-baseline"])).to(eq(1))
        expect(doctor).to(have_received(:baselines))
        expect(out.string).to(include("Baseline: configured test suite is green"))
      end

      it "discovers each framework's default tests" do
        expect(doctor.__send__(:tests_for, framework: "minitest")).to(eq(["test/**/*_test.rb"]))
        expect(doctor.__send__(:tests_for, framework: "rspec")).to(eq(["spec/**/*_spec.rb"]))
      end
    end

    def ci_arguments(argv)
      given = []
      runner = instance_double(Kimera::CLI::Run)
      allow(runner).to(receive(:run) { |arguments| given.replace(arguments).size })
      allow(Kimera::CLI::Run).to(receive(:new).and_return(runner))
      Kimera::CLI::CI.new(io: out, errors: errors, env: {}).run(argv) && given
    end

    it "applies CI defaults only when neither spelling of an override is present" do
      argv = ["--no-fail-on-no-coverage", "--report", "out.json", "--format=ndjson", "--max-survivors=4"]
      expect(ci_arguments(argv)).to(eq(argv))
    end

    it "adds every CI default when no override is given" do
      expect(ci_arguments([])).to(eq(["--max-survivors", "0", "--fail-on-no-coverage", "--format", "github"]))
    end

    it "rejects an invalid completion request" do
      expect(Kimera::CLI::Completion.new(io: out, errors: errors).run(%w[bash extra])).to(eq(1))
      expect(errors.string).to(include("completion <bash|zsh|fish>"))
    end

    it "completes for fish" do
      expect(Kimera::CLI::Completion.new(io: out, errors: errors).run(["fish"])).to(eq(0))
      expect(out.string).to(include("complete -c kimera"))
    end
  end

  describe "report actions and formats" do
    def actions(*results, **where)
      StringIO.new.tap { |io| Kimera::Report::Actions.new(io: io).show(report(*results), **where) }.string
    end

    it "stays silent when clean" do
      expect(actions(result(1, :killed))).to(eq(""))
    end

    it "renders actionable next steps for every problem kind" do
      shown = actions(
        result(8, :survived), result(3, :survived), result(5, :no_coverage), result(9, :harness_error), path: "out.json"
      )
      expect(shown).to(start_with("\nNext actions:\n"))
      expect(shown).to(
        include(
          "2 surviving mutant(s): inspect #3 with `kimera mutant 3 --report out.json`",
          "1 uncovered mutant(s): kimera report out.json --status no_coverage",
          "1 unjudged mutant(s): see why with `kimera mutant 9 --report out.json`"
        )
      )
    end

    it "points at the mutants only a fresh process can judge, saved or not" do
      hint = "\nNext actions:\n  1 #{Kimera::Report::Actions::ISOLATED}\n"
      saved = actions(result(4, :isolated_only), path: "out.json")
      expect([saved, actions(result(4, :isolated_only))]).to(eq([hint, hint]))
    end

    it "points at the mutants only other units' tests reach, saved or not" do
      hint = "1 mutant(s) only other units' tests reach: kimera report out.json --status uncovered_by_unit"
      expect(actions(result(4, :uncovered_by_unit), path: "out.json")).to(eq("\nNext actions:\n  #{hint}\n"))
      expect(actions(result(4, :uncovered_by_unit)))
        .to(include("1 mutant(s) only other units' tests reach: write a unit test that runs each"))
    end

    it "does not invent actions for absent uncovered or unjudged results" do
      expect(actions(result(1, :survived))).not_to(include("uncovered mutant", "unjudged mutant"))
    end

    it "uses fallback action commands when no report path exists" do
      expect(actions(result(1, :survived), result(2, :no_coverage), result(3, :harness_error))).to(
        include(
          "run without --no-report to save one, then `kimera mutant 1`",
          "run without --no-report, then `kimera report --status no_coverage`",
          "unjudged mutant(s): retry with `kimera run --isolated`"
        )
      )
    end

    describe "machine formats" do
      let(:outputs) do
        machine(
          [
            { "mutant_id" => 1, "status" => "survived", "file" => "app/x.rb", "line" => 0, "detail" => "detail" },
            { "mutant_id" => 2, "status" => "no_coverage", "file" => "app/x.rb", "label" => "coverage" },
            { "mutant_id" => 3, "status" => "harness_error", "file" => "app/x.rb", "line" => 4, "label" => "error" },
            { "mutant_id" => 4, "status" => "killed", "file" => "app/x.rb", "line" => 5, "label" => "killed" }
          ]
        )
      end

      it "annotate every problem status for GitHub, and no kill" do
        annotations = outputs.first.string
        expect(annotations).to(include("::error", "::warning", "line=1", "detail"))
        expect(annotations).not_to(include("killed mutant #4"))
      end

      it "level each SARIF result and keep a line of 0" do
        parsed = JSON.parse(outputs[1].string).fetch("runs").first.fetch("results")
        expect(parsed.map { |entry| entry.fetch("level") }).to(eq(%w[error warning warning]))
        expect(parsed.first.dig("locations", 0, "physicalLocation", "region", "startLine")).to(eq(0))
      end

      it "stream the summary, every result and the leaks as NDJSON, with the metadata" do
        records = outputs.last.string.lines.map { |line| JSON.parse(line) }
        expect(records.map { |entry| entry.fetch("type") }).to(eq(%w[summary result result result result leak]))
        expect(records.first.fetch("run")).to(eq("jobs" => 2))
      end
    end

    it "explains unknown report formats with the rejected name and choices" do
      expect { Kimera::Report::Formats.new(io: StringIO.new).emit("xml", report) }
        .to(raise_error(Kimera::UsageError, /xml.*text, json, ndjson, github, sarif/))
    end

    it "omits run metadata from formats when none was supplied" do
      Kimera::Report::Formats.new(io: out).emit("json", report)
      expect(JSON.parse(out.string)).not_to(have_key("run"))
    end
  end

  describe "presentation boundaries" do
    def terminal = StringIO.new.tap { |io| def io.tty? = true }

    it "formats survivor durations at both unit boundaries" do
      expect(Kimera::Duration.new(1.0).brief).to(eq("1.0s"))
      expect(Kimera::Duration.new(0.01).brief).to(eq("10ms"))
      expect(Kimera::Duration.new(0.009).brief).to(eq("9.0ms"))
    end

    it "honors an explicit no-color choice even on a terminal" do
      io = terminal
      registry = Kimera::RegistryScan.new.source("def x(a, b)\n a > b\nend\n", file: "x.rb")
      Kimera::Report::Text.new(registry, io: io, color: false).report(report)
      expect(io.string).not_to(include("\e["))
    end

    def uncolored
      renderer = Kimera::Report::Text.new(Kimera::Registry.new(points: []), io: StringIO.new, color: false)
      allow(renderer).to(receive(:screen).and_return(instance_double(Kimera::Report::Screen, enabled?: true)))
      renderer.__send__(:color?)
    end

    it "forces color off even if the underlying screen reports enabled" do
      expect(uncolored).to(be(false))
    end

    it "forces color off even if the screen is enabled and NO_COLOR is absent" do
      without("NO_COLOR") { expect(uncolored).to(be(false)) }
    end

    it "reports zero-time and positive-time rates and ETAs" do
      tally = Kimera::Report::Tally.new(4, "mutants", 10.0)
      tally.count!(:killed)
      expect(tally.line(10.0)).to(include("rate=—", "ETA —", "0:00"))
      expect(tally.line(12.0)).to(include("0.5/s", "ETA 0:06", "0:02"))
    end

    it "does not show a rate before any work has completed" do
      tally = Kimera::Report::Tally.new(2, "mutants", 1.0)
      expect(tally.line(2.0)).not_to(include("/s"))
    end

    def unfinished
      terminal.tap do |io|
        bar = Kimera::Report::Progress.new(io: io, enabled: true, interval: 0)
        bar.start(2, "mutants")
        bar.tick(:killed)
        bar.finish
      end.string
    end

    it "clears incomplete progress without committing" do
      shown = unfinished
      expect(shown.scan("\r\e[K").size).to(eq(3))
      expect(shown).not_to(end_with("\n"))
    end

    it "commits a live frame once" do
      stream = StringIO.new
      live = Kimera::Report::Live.new(stream).tap { |surface| surface.paint("frame", 0) }
      2.times { live.commit }
      expect(stream.string).to(eq("\r\e[Kframe\n"))
    end

    it "clears a log surface only while it has a drawn frame" do
      io = StringIO.new
      allow(io).to(receive(:flush).and_call_original)
      log = Kimera::Report::Log.new(io).tap { |surface| surface.paint("frame", 0) }
      2.times { log.commit }
      expect(io).to(have_received(:flush).twice)
    end

    it "includes report actions in textual output" do
      registry = Kimera::RegistryScan.new.source("def x(a, b)\n a > b\nend\n", file: "x.rb")
      id = registry.each.first.first.id
      Kimera::Report::Text.new(registry, io: out, color: false)
        .report(Kimera::RunReport.new(results: [result(id, :survived)]), path: "report.json")
      expect(out.string).to(include("Next actions:", "kimera mutant #{id} --report report.json"))
    end
  end

  describe "previously uncovered CLI paths" do
    def doctor(dir)
      FileUtils.mkdir_p(File.join(dir, "test"))
      FileUtils.mkdir_p(File.join(dir, "spec"))
      File.write(File.join(dir, "test", "x_test.rb"), "# test\n")
      File.write(File.join(dir, "spec", "x_spec.rb"), "# spec\n")
      Kimera::CLI::Doctor.new(io: StringIO.new, errors: StringIO.new, root: dir)
    end

    describe "the command wrappers" do
      let(:runner) { instance_double(Kimera::CLI::Init, run: 0) }
      let(:cli) do
        described_class.new(io: StringIO.new, errors: StringIO.new).tap do |cli|
          allow(cli).to(receive(:require_relative))
          allow(described_class).to(receive(:const_get).and_return(class_double(Kimera::CLI::Init, new: runner)))
          allow(Kimera::CLI::Baseline).to(receive(:new).and_return(runner))
        end
      end

      def wrappers = %i[configure doctor changed ci completion baseline]

      it "dispatch every workflow and the baseline to its runner" do
        expect(wrappers.map { |name| cli.__send__(name, []) }).to(eq([0] * 6))
        expect(runner).to(have_received(:run).exactly(6).times)
      end

      it "load the workflows file for each workflow, and the baseline file for baseline" do
        wrappers.each { |name| cli.__send__(name, []) }
        expect(cli).to(have_received(:require_relative).with("cli/workflows").exactly(5).times)
        expect(cli).to(have_received(:require_relative).with("cli/baseline"))
      end

      it "look each workflow's class up by its name" do
        %i[configure completion].each { |name| cli.__send__(name, []) }
        expect(described_class).to(have_received(:const_get).with(:Init))
        expect(described_class).to(have_received(:const_get).with(:Completion))
      end
    end

    it "prints a useful doctor usage error" do
      expect(Kimera::CLI::Doctor.new(io: out, errors: errors).run(["--unknown"])).to(eq(1))
      expect(errors.string).to(include("kimera: invalid option: --unknown"))
    end

    it "builds and diagnoses a successful minitest baseline command" do
      command = [
        Kimera::Execution::SUITE_ENV, "bundle", "exec", "ruby", "-I", "test", "-I", "spec",
        "-e", Kimera::CLI::TestCommand::LOADER, File.join(dir, "test", "x_test.rb")
      ]
      success = ["", instance_double(Process::Status, success?: true)]
      allow(Kimera::Execution::SUITE).to(receive(:call).with(*command, chdir: dir, limit: 125).and_return(success))
      expect(doctor(dir).__send__(:baselines, { framework: "minitest", tests: ["test/**/*_test.rb"] }))
        .to(eq([["✓", "Baseline: configured test suite is green"]]))
      expect(Kimera::Execution::SUITE).to(have_received(:call).with(*command, chdir: dir, limit: 125))
    end

    it "builds and diagnoses a failing RSpec baseline command" do
      command = [Kimera::Execution::SUITE_ENV, "bundle", "exec", "rspec", File.join(dir, "spec", "x_spec.rb")]
      failure = ["noise\n3 examples, 1 failure\n", instance_double(Process::Status, success?: false)]
      allow(Kimera::Execution::SUITE).to(receive(:call).with(*command, chdir: dir, limit: 125).and_return(failure))
      message = "Baseline: 3 examples, 1 failure (fix it, then rerun `kimera doctor --check-baseline`)"
      expect(doctor(dir).__send__(:baselines, { framework: "rspec", tests: ["spec/**/*_spec.rb"] }))
        .to(eq([["✗", message]]))
    end

    def changed_runner
      instance_double(Kimera::CLI::Run, run: 0).tap { |runner| allow(Kimera::CLI::Run).to(receive(:new).and_return(runner)) }
    end

    it "uses the changed-workflow reference" do
      runner = changed_runner
      changed = Kimera::CLI::Changed.new(io: out, errors: errors)
      allow(changed).to(receive(:reference).and_return("origin/main"))
      expect(changed.run(["app"])).to(eq(0))
      expect(runner).to(have_received(:run).with(["--since", "origin/main", "app"]))
    end

    it "keeps an explicit --since=REF" do
      runner = changed_runner
      explicit = Kimera::CLI::Changed.new(io: out, errors: errors).tap { |changed| allow(changed).to(receive(:reference)) }
      explicit.run(["--since=HEAD", "app"])
      expect(explicit).not_to(have_received(:reference))
      expect(runner).to(have_received(:run).with(["--since=HEAD", "app"]))
    end

    it "reads --since in either spelling" do
      expect(Kimera::CLI::Argv.new(["--since", "main"]).option?("--since")).to(be(true))
      expect(Kimera::CLI::Argv.new(["--since=main"]).option?("--since")).to(be(true))
      expect(Kimera::CLI::Argv.new(["app"]).option?("--since")).to(be(false))
    end

    it "prefers origin/main, then main" do
      changed = Kimera::CLI::Changed.new
      allow(changed).to(receive(:system).and_return(true))
      expect(changed.__send__(:reference)).to(eq("origin/main"))
      allow(changed).to(receive(:system).and_return(false, true))
      expect(changed.__send__(:reference)).to(eq("main"))
    end

    it "explains a missing reference" do
      changed = Kimera::CLI::Changed.new
      allow(changed).to(receive(:system).and_return(false, false))
      expect { changed.__send__(:reference) }
        .to(raise_error(Kimera::UsageError, "cannot find origin/main or main; pass --since REF"))
    end
  end

  describe "machine-format escaping" do
    it "percent-encodes every GitHub annotation property delimiter" do
      formats = Kimera::Report::Formats.new(io: StringIO.new)
      expect(formats.__send__(:property, "%\r\n,:")).to(eq("%25%0D%0A%2C%3A"))
    end
  end

  it "rejects a configured baseline path that does not exist" do
    path = File.join(dir, ".kimera.yml")
    File.write(path, "baseline: missing.yml\n")
    expect { Kimera::Config.new(path).options }.to(raise_error(Kimera::UsageError, /no such baseline file/))
  end
end
