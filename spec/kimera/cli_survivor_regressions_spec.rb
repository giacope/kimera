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
  def streams
    [StringIO.new, StringIO.new]
  end

  def result(id, status, **attributes)
    Kimera::MutantResult.new(mutant_id: id, status: status, file: "app/x.rb", duration: 0.0, **attributes)
  end

  def report(*results)
    Kimera::RunReport.new(results: results)
  end

  def fixture(dir, row)
    path = File.join(dir, "report.json")
    File.write(path, JSON.generate("results" => [row]))
    path
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
    it "requires the lazy report and mutant handlers before dispatching" do
      cli = described_class.new(io: StringIO.new, errors: StringIO.new)
      allow(cli).to(receive(:require_relative))
      allow(Kimera::CLI::Survivors).to(receive(:new).and_return(instance_double(Kimera::CLI::Survivors, run: 0)))
      allow(Kimera::CLI::Mutant).to(receive(:new).and_return(instance_double(Kimera::CLI::Mutant, run: 0)))
      cli.__send__(:report, ["report.json"])
      cli.__send__(:mutant, ["1", "--report", "report.json"])
      expect(cli).to(have_received(:require_relative).with("cli/survivors"))
      expect(cli).to(have_received(:require_relative).with("cli/mutant"))
    end

    it "suggests a command exactly three edits away, but not a distant one" do
      out, errors = streams
      cli = described_class.new(io: out, errors: errors)
      expect(Kimera::CLI::Suggestion.new(["run"]).hint("rxxx")).to(eq('; did you mean "run"?'))
      expect(cli.run(["rxxx"])).to(eq(1))
      expect(errors.string).to(include('did you mean "run"?'))

      errors.truncate(0)
      errors.rewind
      cli.run(["completely-unknown"])
      expect(errors.string).not_to(include("did you mean"))
    end

    it "loads report and mutant handlers when the base CLI is loaded alone" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "report.json")
        row = { "mutant_id" => 1, "status" => "survived", "file" => "x.rb", "label" => "x", "original" => "x" }
        File.write(path, JSON.generate("results" => [row]))
        script = <<~RUBY
          require "kimera/cli"
          report = ARGV.fetch(0)
          abort("report failed") unless Kimera::CLI.new.run(["report", report]).zero?
          abort("mutant failed") unless Kimera::CLI.new.run(["mutant", "1", "--report", report]).zero?
        RUBY
        output, status = Open3.capture2e(Gem.ruby, "-I", File.expand_path("../../lib", __dir__), "-e", script, path)
        expect(status).to(be_success, output)
        expect(output).to(include("1 survived mutant(s):", "#1  survived"))
      end
    end
  end

  describe "baseline validation" do
    def baseline(argv, out: StringIO.new, errors: StringIO.new)
      [Kimera::CLI::Baseline.new(io: out, errors: errors).run(argv), out.string, errors.string]
    end

    it "rejects every invalid create input" do
      Dir.mktmpdir do |dir|
        source = fixture(dir, "mutant_id" => 9, "status" => "survived", "file" => "x.rb", "line" => 2, "label" => "x")
        Dir.chdir(dir) do
          expect(baseline(["create"])[2]).to(include("needs a report file"))
          expect(baseline(["create", source])[2]).to(include("requires --reason"))
          expect(baseline(["create", "missing.json", "--reason", "why"])[2]).to(include("no such report"))
        end
      end
    end

    it "creates a baseline and refuses to replace it implicitly" do
      Dir.mktmpdir do |dir|
        source = fixture(dir, "mutant_id" => 9, "status" => "survived", "file" => "x.rb", "line" => 2, "label" => "x")
        target = File.join(dir, "baseline.yml")
        status, output, = baseline(["create", source, "--reason", "why", "--output", target])
        expect(status).to(eq(0))
        expect(output).to(include("Created #{target} with 1 accepted survivor(s).", "baseline: #{target}"))
        expect(baseline(["create", source, "--reason", "why", "--output", target])[2]).to(include("already exists"))
      end
    end

    it "rejects incomplete reports and invalid review invocations" do
      Dir.mktmpdir do |dir|
        bad = File.join(dir, "bad.json")
        File.write(bad, JSON.generate("results" => [{ "mutant_id" => 1, "status" => "survived", "file" => "x.rb" }]))
        argv = ["create", bad, "--reason", "why", "--output", File.join(dir, "baseline.yml")]
        expect(baseline(argv)[2]).to(include("report is missing line for mutant #1"))
        expect(baseline(["review"])[2]).to(include("Usage: kimera baseline review BASELINE.yml"))
        expect(baseline(["review", "missing.yml"])[2]).to(include("no such baseline"))
      end
    end
  end

  describe "mutant reruns" do
    def rerun(settings)
      row = { "file" => "app/x.rb", "key" => "app/x.rb:1:0123abcd" }
      Kimera::CLI::Mutant.new.__send__(:arguments_for, row, settings)
    end

    it "validates required inputs and preserves coverage and isolation provenance" do
      out, errors = streams
      cli = Kimera::CLI::Mutant.new(io: out, errors: errors)
      expect(cli.run([])).to(eq(1))
      expect(errors.string).to(include("mutant ID is required"))
      errors.truncate(0)
      errors.rewind
      Dir.mktmpdir { |dir| Dir.chdir(dir) { expect(cli.run(["7"])).to(eq(1)) } }
      expect(errors.string).to(include("no such report: tmp/kimera/report.json (run kimera run first"))

      args = rerun(
        "framework" => "minitest", "source_root" => "src", "tests" => ["test/a_test.rb"],
        "operators" => ["comparison"], "coverage" => false, "isolated" => true
      )
      expect(args).to(include("--no-coverage", "--isolated", "--framework", "minitest", "--source-root", "src"))
      expect(args.first(3)).to(eq(["app/x.rb", "--focus", "app/x.rb:1:0123abcd"]))
    end

    it "asks for a fresh report when the rerun row predates mutant keys" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "report.json")
        File.write(path, JSON.generate("run" => {}, "results" => [{ "mutant_id" => 7, "file" => "x.rb" }]))
        out, errors = streams
        expect(Kimera::CLI::Mutant.new(io: out, errors: errors).run(["7", "--report", path, "--rerun"])).to(eq(1))
        expect(errors.string)
          .to(eq("kimera: report has no mutant keys; regenerate it with kimera run --report, then rerun\n"))
        expect(out.string).to(be_empty)
      end
    end

    it "rejects reports without the requested mutant, source, or provenance" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "report.json")
        out, errors = streams
        cli = Kimera::CLI::Mutant.new(io: out, errors: errors)
        [
          [[], "no mutant #7"], [[{ "mutant_id" => 7 }], "has no source file"],
          [[{ "mutant_id" => 7, "file" => "x.rb" }], "has no run provenance"]
        ].each do |rows, message|
          File.write(path, JSON.generate("results" => rows))
          expect(cli.run(["7", "--report", path, "--rerun"])).to(eq(1))
          expect(errors.string).to(include(message))
          errors.truncate(0)
          errors.rewind
        end
      end
    end
  end

  describe "run argument, cycle, and digest boundaries" do
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
      registry = Kimera::RegistryScan.new.source("def x; 1; end\n", file: "x.rb")
      narration = StringIO.new
      output = StringIO.new
      emission = Kimera::CLI::Run::Emission.new(io: narration, output: output)
      emission.emit(report, registry, format: "json", metadata: { "framework" => "rspec" })
      expect(narration.string).to(eq(""))
      expect(JSON.parse(output.string).fetch("run")).to(eq("framework" => "rspec"))
    end

    it "chooses the error stream for a machine format and defaults gate to enabled" do
      narration = StringIO.new
      errors = StringIO.new
      cli = Kimera::CLI::Run.new(io: narration, errors: errors)
      expect(cli.__send__(:digest, format: "json").instance_variable_get(:@io)).to(equal(errors))
      registry = Kimera::RegistryScan.new.source("def x; 1; end\n", file: "x.rb")
      loaded = instance_double(Kimera::Incremental::Session, report: report)
      digest = instance_double(Kimera::CLI::Run::Digest, emit: nil, gate: 7)
      options = {
        report: nil, json: nil, format: "text", fail_on_no_coverage: false, quiet: false, log: nil,
        framework: "rspec", source_root: ".", tests: [], exclude_tests: [], operators: [],
        coverage: true, isolated: false, jobs: 1
      }
      cycle = Kimera::CLI::Run::Cycle.new(options, registry, nil, digest: digest)
      expect(cycle.__send__(:conclude, [], [], loaded)).to(eq(7))
      expect(digest).to(have_received(:gate))
      expect(digest).to(have_received(:emit).with(anything, registry, **emission(:hint)))
      strict = Kimera::CLI::Run::Cycle.new(options.merge(fail_on_no_coverage: true), registry, nil, digest: digest)
      strict.__send__(:conclude, [], [], loaded)
      expect(digest).to(have_received(:emit).with(anything, registry, **emission(:list)))
    end

    def emission(coverage)
      { coverage: coverage, path: nil, format: "text", metadata: anything, log: nil, scope: nil, summary: nil }
    end

    it "writes report metadata only when supplied and respects color overrides" do
      registry = Kimera::RegistryScan.new.source("def x; 1; end\n", file: "x.rb")
      Dir.mktmpdir do |dir|
        plain = File.join(dir, "plain.json")
        annotated = File.join(dir, "annotated.json")
        Kimera::CLI::Run::Emission.new(io: StringIO.new).emit(report, registry, path: plain)
        options = { path: annotated, metadata: { "jobs" => 2 } }
        Kimera::CLI::Run::Emission.new(io: StringIO.new).emit(report, registry, **options)
        expect(JSON.parse(File.read(plain))).not_to(have_key("run"))
        expect(JSON.parse(File.read(annotated)).to_h.fetch("run")).to(eq("jobs" => 2))
      end
      expect(Kimera::CLI::Run::Emission.new(color: false).__send__(:color?)).to(be(false))
      expect(Kimera::CLI::Run::Emission.new(color: true).__send__(:color?)).to(be(true))
      original = ENV.delete("NO_COLOR")
      expect(Kimera::CLI::Run::Emission.new(io: StringIO.new).__send__(:color?)).to(be(false))
    ensure
      ENV["NO_COLOR"] = original if original
    end

    it "records verbose paths and tests, including empty lists" do
      io = StringIO.new
      Kimera::CLI::Run::Digest.new(io: io, emission: nil).verbose(
        framework: "rspec", jobs: 1, paths: ["app/**/*.rb"],
        tests: ["spec/x_spec.rb"], format: "text"
      )
      expect(io.string).to(include("sources=app/**/*.rb tests=spec/x_spec.rb format=text"))
    end

    it "only calls the gate when enabled, and records complete provenance" do
      registry = Kimera::RegistryScan.new.source("def x; 1; end\n", file: "x.rb")
      loaded = instance_double(Kimera::Incremental::Session, report: report)
      digest = instance_double(Kimera::CLI::Run::Digest, emit: nil, gate: 9)
      base = {
        report: nil, json: nil, format: "text", fail_on_no_coverage: false, quiet: false, log: nil,
        framework: "rspec", source_root: ".", tests: ["spec/**/*_spec.rb"], exclude_tests: [],
        operators: ["comparison"], coverage: true, isolated: false, jobs: 1
      }
      disabled = Kimera::CLI::Run::Cycle.new(base.merge(gate: false), registry, nil, digest: digest)
      expect(disabled.__send__(:conclude, [], [], loaded)).to(eq(0))
      expect(digest).not_to(have_received(:gate))
      enabled = Kimera::CLI::Run::Cycle.new(base.merge(gate: true), registry, nil, digest: digest)
      expect(enabled.__send__(:conclude, [], [], loaded)).to(eq(9))
      expect(enabled.__send__(:provenance)).to(
        eq(
          "framework" => "rspec", "source_root" => ".", "tests" => ["spec/**/*_spec.rb"],
          "exclude_tests" => [], "operators" => ["comparison"], "coverage" => true,
          "isolated" => false, "jobs" => 1, "narrowed" => false
        )
      )
    end

    it "runs verbose setup only when requested and validates focused IDs" do
      registry = Kimera::RegistryScan.new.source("def x; 1; end\n", file: "x.rb")
      digest = instance_double(Kimera::CLI::Run::Digest, verbose: nil)
      quiet = Kimera::CLI::Run::Cycle.new({ verbose: false }, registry, nil, digest: digest)
      allow(quiet).to(receive(:scope))
      quiet.call
      expect(digest).not_to(have_received(:verbose))
      loud = Kimera::CLI::Run::Cycle.new({ verbose: true }, registry, nil, digest: digest)
      allow(loud).to(receive(:scope))
      loud.call
      expect(digest).to(have_received(:verbose).with(verbose: true))
      expect(loud.__send__(:focus, [1, 2])).to(eq([1, 2]))
      focused = Kimera::CLI::Run::Cycle.new({ focus: [1] }, registry, nil, digest: digest)
      expect(focused.__send__(:focus, [1, 2])).to(eq([1]))
      expect { Kimera::CLI::Run::Cycle.new({ focus: [3] }, registry, nil, digest: digest).__send__(:focus, [1, 2]) }
        .to(raise_error(Kimera::UsageError, /3/))
    end

    it "focuses by ordinal or key, follows a key whose line moved, and rejects an unknown key" do
      registry = Kimera::RegistryScan.new.source("def x(a)\n  a > 1\nend\n", file: "x.rb")
      key = registry.keys[1]
      focus =
        lambda do |tokens|
          Kimera::CLI::Run::Cycle.new({ focus: tokens }, registry, nil, digest: nil).__send__(:focus, [1, 2, 3])
        end
      expect(key).to(start_with("x.rb:2:"))
      expect(focus.call([key, "2"])).to(eq([1, 2]))
      expect(focus.call([key.sub(":2:", ":7:")])).to(eq([1]))
      expect { focus.call(["x.rb:2:ffffffff", "3"]) }
        .to(raise_error(Kimera::UsageError, "focused mutant(s) not in scope: x.rb:2:ffffffff"))
    end

    # `.rspec`'s `--require spec_helper` loads the helper while the adapter is
    # built, so a coverage floor gated on KIMERA must see it before then.
    it "sets KIMERA before loading the framework adapter" do
      registry = Kimera::RegistryScan.new.source("def x; 1; end\n", file: "x.rb")
      cycle = Kimera::CLI::Run::Cycle.new({ framework: "rspec" }, registry, nil, digest: nil)
      env = {}
      seen = nil
      allow(Kimera::Frameworks::ADAPTERS).to(receive(:load) { seen = env["KIMERA"] })
      allow(Kimera::CLI::Run::Pass).to(receive(:new).and_return(instance_double(Kimera::CLI::Run::Pass, call: nil)))
      cycle.__send__(:harness, [1], nil, env: env)
      expect(seen).to(eq("1"))
    end
  end

  describe "workflow branches" do
    it "initializes minitest projects, supports dry-run, and rejects unknown options" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "test"))
        File.write(File.join(dir, "thing.rb"), "class Thing; end\n")
        out, errors = streams
        init = Kimera::CLI::Init.new(io: out, errors: errors, root: dir)
        expect(init.run(["--dry-run"])).to(eq(0))
        expect(out.string).to(include("framework: minitest", "paths:", "lib/**/*.rb", "fail_on_no_coverage: false"))
        expect(YAML.safe_load(out.string).fetch("tests")).to(eq(["test/**/*_test.rb"]))
        expect(File).not_to(exist(File.join(dir, ".kimera.yml")))
        expect(init.run(["--bogus"])).to(eq(1))
      end
    end

    it "detects RSpec when both test directories exist and names the chosen framework" do
      Dir.mktmpdir do |dir|
        %w[test spec app].each { |name| FileUtils.mkdir_p(File.join(dir, name)) }
        File.write(File.join(dir, "app", "x.rb"), "class X; end\n")
        out, errors = streams
        init = Kimera::CLI::Init.new(io: out, errors: errors, root: dir)
        expect(init.run([])).to(eq(0))
        expect(out.string).to(
          eq("Created .kimera.yml for rspec.\nPointed AI agents to `kimera skill` in AGENTS.md.\nNext: kimera doctor\n")
        )
        expect(YAML.safe_load_file(File.join(dir, ".kimera.yml")).fetch("tests")).to(eq(["spec/**/*_spec.rb"]))
      end
    end

    it "reports broken doctor checks" do
      Dir.mktmpdir do |dir|
        out, errors = streams
        doctor = Kimera::CLI::Doctor.new(io: out, errors: errors, root: dir)
        expect(doctor.run([])).to(eq(1))
        expect(out.string).to(
          include(
            "Configuration: none found", "Source scope: no Ruby files",
            "Test discovery: no test files", "not a repository", "no Rails-specific"
          )
        )
        expect(errors.string).to(include("doctor found 2 blocking issue(s)"))
      end
    end

    it "reports healthy doctor checks" do
      Dir.mktmpdir do |dir|
        %w[app spec config .git].each { |name| FileUtils.mkdir_p(File.join(dir, name)) }
        File.write(File.join(dir, "app", "x.rb"), "class X; end\n")
        File.write(File.join(dir, "spec", "x_spec.rb"), "# spec\n")
        File.write(File.join(dir, "config", "application.rb"), "# rails\n")
        File.write(
          File.join(dir, ".kimera.yml"),
          "framework: rspec\npaths: [app/**/*.rb]\ntests: [spec/**/*_spec.rb]\n"
        )
        out = StringIO.new
        doctor = Kimera::CLI::Doctor.new(io: out, errors: StringIO.new, root: dir)
        expect(doctor.run([])).to(eq(0))
        expect(out.string).to(
          include(
            "Configuration: .kimera.yml (rspec)", "Git: incremental runs are available",
            "Rails detected"
          )
        )
      end
    end

    it "fails when a test file cannot load, and accepts a worktree's .git file", :aggregate_failures do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "spec"))
        File.write(File.join(dir, "spec", "x_spec.rb"), "# spec\n")
        File.write(File.join(dir, ".git"), "gitdir: /elsewhere\n")
        failure = instance_double(Process::Status, success?: false)
        allow(Open3).to(receive(:capture2e).and_return(["x_spec.rb:1: boom (RuntimeError)\n", failure]))
        out, errors = streams
        expect(Kimera::CLI::Doctor.new(io: out, errors: errors, root: dir).run([])).to(eq(1))
        expect(out.string).to(include("✗ Test loading: x_spec.rb:1: boom (RuntimeError)", "✓ Git: incremental"))
      end
    end

    it "runs the baseline check only when requested and discovers minitest defaults" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "spec"))
        File.write(File.join(dir, "spec", "x_spec.rb"), "# spec\n")
        allow(Open3).to(receive(:capture2e).and_return(["", instance_double(Process::Status, success?: true)]))
        out, errors = streams
        doctor = Kimera::CLI::Doctor.new(io: out, errors: errors, root: dir)
        allow(doctor).to(receive(:baselines).and_return([["✓", "Baseline: configured test suite is green"]]))
        expect(doctor.run([])).to(eq(1))
        expect(doctor).not_to(have_received(:baselines))
        out.truncate(0)
        out.rewind
        expect(doctor.run(["--check-baseline"])).to(eq(1))
        expect(doctor).to(have_received(:baselines))
        expect(out.string).to(include("Baseline: configured test suite is green"))
        expect(doctor.__send__(:tests_for, framework: "minitest")).to(eq(["test/**/*_test.rb"]))
        expect(doctor.__send__(:tests_for, framework: "rspec")).to(eq(["spec/**/*_spec.rb"]))
      end
    end

    it "applies CI defaults only when neither spelling of an override is present" do
      out, errors = streams
      runner = instance_double(Kimera::CLI::Run, run: 0)
      allow(Kimera::CLI::Run).to(receive(:new).and_return(runner))
      Kimera::CLI::CI.new(
        io: out,
        errors: errors,
        env: {}
      ).run(
        [
          "--no-fail-on-no-coverage", "--report",
          "out.json", "--format=ndjson", "--max-survivors=4"
      ]
      )
      expect(runner).to(
        have_received(:run).with(
        [
          "--no-fail-on-no-coverage", "--report", "out.json", "--format=ndjson",
          "--max-survivors=4"
      ]
      )
      )
    end

    it "adds every CI default when no override is given" do
      out, errors = streams
      runner = instance_double(Kimera::CLI::Run, run: 0)
      allow(Kimera::CLI::Run).to(receive(:new).and_return(runner))
      Kimera::CLI::CI.new(io: out, errors: errors, env: {}).run([])
      expect(runner).to(
        have_received(:run).with(
        [
          "--max-survivors", "0", "--fail-on-no-coverage", "--format", "github"
      ]
      )
      )
    end

    it "rejects invalid completion requests" do
      out, errors = streams
      cli = Kimera::CLI::Completion.new(io: out, errors: errors)
      expect(cli.run(%w[bash extra])).to(eq(1))
      expect(errors.string).to(include("completion <bash|zsh|fish>"))
      expect(cli.run(["fish"])).to(eq(0))
      expect(out.string).to(include("complete -c kimera"))
    end
  end

  describe "report actions and formats" do
    it "renders actionable next steps for every problem kind and stays silent when clean" do
      io = StringIO.new
      actions = Kimera::Report::Actions.new(io: io)
      actions.show(report(result(1, :killed)))
      expect(io.string).to(eq(""))
      actions.show(
        report(
          result(8, :survived), result(3, :survived), result(5, :no_coverage),
          result(9, :harness_error)
        ), path: "out.json"
      )
      expect(io.string).to(start_with("\nNext actions:\n"))
      expect(io.string).to(
        include(
          "2 surviving mutant(s): inspect #3 with `kimera mutant 3 --report out.json`",
          "1 uncovered mutant(s): kimera report out.json --status no_coverage",
          "1 unjudged mutant(s): see why with `kimera mutant 9 --report out.json`"
        )
      )
    end

    it "does not invent actions for absent uncovered or unjudged results" do
      io = StringIO.new
      Kimera::Report::Actions.new(io: io).show(report(result(1, :survived)))
      expect(io.string).not_to(include("uncovered mutant", "unjudged mutant"))
    end

    it "uses fallback action commands when no report path exists" do
      io = StringIO.new
      Kimera::Report::Actions.new(io: io).show(
        report(result(1, :survived), result(2, :no_coverage), result(3, :harness_error))
      )
      expect(io.string).to(
        include(
          "run without --no-report to save one, then `kimera mutant 1`",
          "run without --no-report, then `kimera report --status no_coverage`",
          "unjudged mutant(s): retry with `kimera run --isolated`"
        )
      )
    end

    it "emits every machine-readable problem status, fallback field, leak, and metadata" do
      rows = [
        { "mutant_id" => 1, "status" => "survived", "file" => "app/x.rb", "line" => 0, "detail" => "detail" },
        { "mutant_id" => 2, "status" => "no_coverage", "file" => "app/x.rb", "label" => "coverage" },
        { "mutant_id" => 3, "status" => "harness_error", "file" => "app/x.rb", "line" => 4, "label" => "error" },
        { "mutant_id" => 4, "status" => "killed", "file" => "app/x.rb", "line" => 5, "label" => "killed" }
      ]
      annotations, findings, stream = machine(rows)
      expect(annotations.string).to(include("::error", "::warning", "line=1", "detail"))
      expect(annotations.string).not_to(include("killed mutant #4"))
      parsed = JSON.parse(findings.string).fetch("runs").first.fetch("results")
      expect(parsed.map { |entry| entry.fetch("level") }).to(eq(%w[error warning warning]))
      expect(parsed.first.dig("locations", 0, "physicalLocation", "region", "startLine")).to(eq(0))
      records = stream.string.lines.map { |line| JSON.parse(line) }
      expect(records.map { |entry| entry.fetch("type") }).to(eq(%w[summary result result result result leak]))
      expect(records.first.fetch("run")).to(eq("jobs" => 2))
    end

    it "explains unknown report formats with the rejected name and choices" do
      expect { Kimera::Report::Formats.new(io: StringIO.new).emit("xml", report) }
        .to(raise_error(Kimera::UsageError, /xml.*text, json, ndjson, github, sarif/))
    end

    it "omits run metadata from formats when none was supplied" do
      io = StringIO.new
      Kimera::Report::Formats.new(io: io).emit("json", report)
      expect(JSON.parse(io.string)).not_to(have_key("run"))
    end
  end

  describe "presentation boundaries" do
    it "formats survivor durations at both unit boundaries" do
      expect(Kimera::Duration.new(1.0).brief).to(eq("1.0s"))
      expect(Kimera::Duration.new(0.01).brief).to(eq("10ms"))
      expect(Kimera::Duration.new(0.009).brief).to(eq("9.0ms"))
    end

    it "honors an explicit no-color choice even on a terminal" do
      io = StringIO.new
      def io.tty? = true
      registry = Kimera::RegistryScan.new.source("def x(a, b)\n a > b\nend\n", file: "x.rb")
      Kimera::Report::Text.new(registry, io: io, color: false).report(report)
      expect(io.string).not_to(include("\e["))
    end

    it "forces color off even if the underlying screen reports enabled" do
      renderer = Kimera::Report::Text.new(Kimera::Registry.new(points: []), io: StringIO.new, color: false)
      allow(renderer).to(receive(:screen).and_return(instance_double(Kimera::Report::Screen, enabled?: true)))
      expect(renderer.__send__(:color?)).to(be(false))
    ensure
      ENV["NO_COLOR"] = original_no_color if defined?(original_no_color) && original_no_color
    end

    it "forces color off even if the screen is enabled and NO_COLOR is absent" do
      original = ENV.delete("NO_COLOR")
      renderer = Kimera::Report::Text.new(Kimera::Registry.new(points: []), io: StringIO.new, color: false)
      allow(renderer).to(receive(:screen).and_return(instance_double(Kimera::Report::Screen, enabled?: true)))
      expect(renderer.__send__(:color?)).to(be(false))
    ensure
      ENV["NO_COLOR"] = original if original
    end

    it "reports zero-time and positive-time rates and ETAs" do
      tally = Kimera::Report::Tally.new
      tally.begin!(4, "mutants", 10.0)
      tally.count!(:killed)
      at_start = tally.line(10.0)
      later = tally.line(12.0)
      expect(at_start).to(include("rate=—", "ETA —", "0:00"))
      expect(later).to(include("0.5/s", "ETA 0:06", "0:02"))
    end

    it "does not show a rate before any work has completed" do
      tally = Kimera::Report::Tally.new
      tally.begin!(2, "mutants", 1.0)
      expect(tally.line(2.0)).not_to(include("/s"))
    end

    it "clears incomplete progress without committing, and commits a live frame once" do
      io = StringIO.new
      def io.tty? = true
      bar = Kimera::Report::Progress.new(io: io, enabled: true, interval: 0)
      bar.start(2, "mutants")
      bar.tick(:killed)
      bar.finish
      expect(io.string.scan("\r\e[K").size).to(eq(3))
      expect(io.string).not_to(end_with("\n"))

      stream = StringIO.new
      live = Kimera::Report::Live.new(stream)
      live.paint("frame", 0)
      live.commit
      live.commit
      expect(stream.string).to(eq("\r\e[Kframe\n"))
    end

    it "clears a log surface only while it has a drawn frame" do
      io = StringIO.new
      allow(io).to(receive(:flush).and_call_original)
      log = Kimera::Report::Log.new(io)
      log.paint("frame", 0)
      log.commit
      log.commit
      expect(io).to(have_received(:flush).twice)
    end

    it "includes report actions in textual output" do
      registry = Kimera::RegistryScan.new.source("def x(a, b)\n a > b\nend\n", file: "x.rb")
      mutant = registry.each.first.first
      io = StringIO.new
      Kimera::Report::Text.new(registry, io: io, color: false).report(
        Kimera::RunReport.new(results: [result(mutant.id, :survived)]), path: "report.json"
      )
      expect(io.string).to(include("Next actions:", "kimera mutant #{mutant.id} --report report.json"))
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

    it "dispatches every workflow wrapper and the baseline wrapper" do
      cli = described_class.new(io: StringIO.new, errors: StringIO.new)
      runner = instance_double(Kimera::CLI::Init, run: 0)
      handler = class_double(Kimera::CLI::Init, new: runner)
      allow(cli).to(receive(:require_relative))
      allow(described_class).to(receive(:const_get).and_return(handler))
      allow(Kimera::CLI::Baseline).to(receive(:new).and_return(runner))

      expect(cli.__send__(:init, [])).to(eq(0))
      expect(cli.__send__(:doctor, [])).to(eq(0))
      expect(cli.__send__(:changed, [])).to(eq(0))
      expect(cli.__send__(:ci, [])).to(eq(0))
      expect(cli.__send__(:completion, [])).to(eq(0))
      expect(cli.__send__(:baseline, [])).to(eq(0))
      expect(cli).to(have_received(:require_relative).with("cli/workflows").exactly(5).times)
      expect(cli).to(have_received(:require_relative).with("cli/baseline"))
      expect(described_class).to(have_received(:const_get).with(:Init))
      expect(described_class).to(have_received(:const_get).with(:Completion))
      expect(runner).to(have_received(:run).exactly(6).times)
    end

    it "prints a useful doctor usage error" do
      out, errors = streams
      expect(Kimera::CLI::Doctor.new(io: out, errors: errors).run(["--unknown"])).to(eq(1))
      expect(errors.string).to(include("kimera: invalid option: --unknown"))
    end

    it "builds and diagnoses a successful minitest baseline command" do
      Dir.mktmpdir do |dir|
        instance = doctor(dir)
        success = instance_double(Process::Status, success?: true)
        test = File.join(dir, "test", "x_test.rb")
        loader = Kimera::CLI::TestCommand::LOADER
        command = [Kimera::Execution::SUITE_ENV, "bundle", "exec", "ruby", "-Itest", "-e", loader, test]
        allow(Open3).to(receive(:capture2e).with(*command, chdir: dir).and_return(["", success]))

        result = instance.__send__(:baselines, { framework: "minitest", tests: ["test/**/*_test.rb"] })

        expect(result).to(eq([["✓", "Baseline: configured test suite is green"]]))
        expect(Open3).to(have_received(:capture2e).with(*command, chdir: dir))
      end
    end

    it "builds and diagnoses a failing RSpec baseline command" do
      Dir.mktmpdir do |dir|
        instance = doctor(dir)
        failure = instance_double(Process::Status, success?: false)
        spec = File.join(dir, "spec", "x_spec.rb")
        command = ["bundle", "exec", "rspec", spec]
        allow(Open3).to(
          receive(:capture2e).with(
            Kimera::Execution::SUITE_ENV, *command,
            chdir: dir
          ).and_return(["noise\n3 examples, 1 failure\n", failure])
        )

        result = instance.__send__(:baselines, { framework: "rspec", tests: ["spec/**/*_spec.rb"] })

        message = "Baseline: 3 examples, 1 failure (fix it, then rerun `kimera doctor --check-baseline`)"
        expect(result).to(eq([["✗", message]]))
        expect(Open3).to(have_received(:capture2e).with(Kimera::Execution::SUITE_ENV, *command, chdir: dir))
      end
    end

    it "uses the changed-workflow reference unless either --since spelling was supplied" do
      out, errors = streams
      runner = instance_double(Kimera::CLI::Run, run: 0)
      allow(Kimera::CLI::Run).to(receive(:new).and_return(runner))
      changed = Kimera::CLI::Changed.new(io: out, errors: errors)
      allow(changed).to(receive(:reference).and_return("origin/main"))
      expect(changed.run(["app"])).to(eq(0))
      expect(runner).to(have_received(:run).with(["--since", "origin/main", "app"]))

      explicit = Kimera::CLI::Changed.new(io: out, errors: errors)
      allow(explicit).to(receive(:reference))
      explicit.run(["--since=HEAD", "app"])
      expect(explicit).not_to(have_received(:reference))
      expect(runner).to(have_received(:run).with(["--since=HEAD", "app"]))
      expect(Kimera::CLI::Argv.option?(["--since", "main"], "--since")).to(be(true))
      expect(Kimera::CLI::Argv.option?(["--since=main"], "--since")).to(be(true))
      expect(Kimera::CLI::Argv.option?(["app"], "--since")).to(be(false))
    end

    it "prefers origin/main, then main, and otherwise explains the missing reference" do
      changed = Kimera::CLI::Changed.new
      allow(changed).to(receive(:system).and_return(true))
      expect(changed.__send__(:reference)).to(eq("origin/main"))

      allow(changed).to(receive(:system).and_return(false, true))
      expect(changed.__send__(:reference)).to(eq("main"))

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
    Dir.mktmpdir do |dir|
      path = File.join(dir, ".kimera.yml")
      File.write(path, "baseline: missing.yml\n")
      expect { Kimera::Config.load(path) }.to(raise_error(Kimera::UsageError, /no such baseline file/))
    end
  end
end
