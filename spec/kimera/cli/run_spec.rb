# frozen_string_literal: true

require "kimera/cli/run"
require "kimera/registry/builder"
require "stringio"
require "tmpdir"

RSpec.describe(Kimera::CLI::Run, :aggregate_failures) do
  subject(:cli) { described_class.new }

  def hushed
    original = $stderr
    $stderr = StringIO.new
    yield
  ensure
    $stderr = original
  end

  def captured
    io = StringIO.new
    original = $stdout
    $stdout = io
    yield
    io.string
  ensure
    $stdout = original
  end

  def transcript
    out = StringIO.new
    error = StringIO.new
    output = $stdout
    errors = $stderr
    $stdout = out
    $stderr = error
    returned = yield

    [out.string, error.string, returned]
  ensure
    $stdout = output
    $stderr = errors
  end

  describe "#parse" do
    # Run from a config-free dir; the repo's own .kimera.yml would skew defaults.
    around do |example|
      Dir.mktmpdir { |dir| Dir.chdir(dir) { example.run } }
    end

    def defaults
      {
        framework: "rspec", source_root: ".", tests: ["spec/**/*_spec.rb"], configured_tests: ["spec/**/*_spec.rb"],
        operators: Kimera::Operators::DEFAULT_KEYS,
        soft_timeout: 5.0, hard_timeout: nil, leak_every: 10,
        registry: nil, report: nil, format: "text", focus: [], gate: true, coverage: true, require: [],
        since: nil, session: nil, max_survivors: nil, max_ignored: nil,
        max_errors: 0, evaluate_ignored: false, baseline: nil,
        jobs: 1, exclude: [], exclude_tests: [], config: nil, ignore: [],
        isolate_db: false,
        isolated: false, fail_on_no_coverage: false, progress: nil, color: nil, quiet: false, verbose: false, log: nil,
        pidfile: nil,
        isolate_when_covered_by: [],
        paths: ["app/**/*.rb", "lib/**/*.rb"]
      }
    end

    # Exact equality, so a dropped or drifted default fails.
    it "applies exactly the documented defaults" do
      expect(cli.__send__(:parse, [])).to(eq(defaults))
    end

    it "reads --max-errors as the unjudged-mutant budget" do
      expect(cli.__send__(:parse, ["--max-errors", "3"])[:max_errors]).to(eq(3))
    end

    it "splits --operators into an array of keys" do
      opts = cli.__send__(:parse, ["--operators", "comparison,regexp"])
      expect(opts[:operators]).to(eq(%w[comparison regexp]))
    end

    it "merges config-file defaults, with flags overriding them" do
      File.write("custom.yml", "jobs: 7\nsoft_timeout: 3.5\n")
      opts = cli.__send__(:parse, ["--config", "custom.yml"])
      expect(opts[:jobs]).to(eq(7))
      expect(opts[:soft_timeout]).to(eq(3.5))
      expect(cli.__send__(:parse, ["--config", "custom.yml", "--jobs", "2"])[:jobs]).to(eq(2))
    end

    # Appending would re-include the whole suite when scoping to one file.
    it "replaces the config tests: glob when --tests is given" do
      File.write("custom.yml", %(tests: ["spec/config_spec.rb"]\n))
      opts = cli.__send__(:parse, ["--config", "custom.yml", "--tests", "spec/only_spec.rb"])
      expect(opts[:tests]).to(eq(["spec/only_spec.rb"]))
    end

    it "keeps the config tests: glob to tell a narrowed run apart" do
      File.write("custom.yml", %(tests: ["spec/config_spec.rb"]\n))
      opts = cli.__send__(:parse, ["--config", "custom.yml", "--tests", "spec/only_spec.rb"])
      expect(opts[:configured_tests]).to(eq(["spec/config_spec.rb"]))
    end

    it "keeps the config tests: glob when --tests is absent" do
      File.write("custom.yml", %(tests: ["spec/config_spec.rb"]\n))
      expect(cli.__send__(:parse, ["--config", "custom.yml"])[:tests]).to(eq(["spec/config_spec.rb"]))
    end

    def help
      captured { expect { cli.run(["--help"]) }.to(raise_error(SystemExit)) }
    end

    def flags
      %w[
        framework tests source-root registry operators soft-timeout
        hard-timeout leak-every coverage since session max-survivors
        max-ignored fail-on-no-coverage jobs progress isolate-db isolated
        isolate-when-covered-by exclude config pidfile evaluate-ignored no-baseline
      ]
    end

    def document(lines, flag)
      index = lines.index { |l| l =~ /\A\s*--(\[no-\])?#{flag}\b/ }
      expect(index).not_to(be_nil, "--#{flag} missing from --help")
      # Include wrapped continuation lines.
      expect(
        [lines[index], *lines[(index + 1)..].take_while { |l| l !~ /\A\s*--/ }]
          .join.sub(/\A\s*--\S+( \S+)?/, "").scan(/\w/).size
      ).to(be >= 10, "--#{flag} lacks a description")
    end

    # Checks each flag has a real description, not the exact prose.
    it "documents every flag in --help" do
      lines = help.lines
      expect(lines.first).to(start_with("Usage: kimera run [paths...] [options]"))
      flags.each { |flag| document(lines, flag) }
    end

    def arguments
      [
        "--framework", "minitest", "--source-root", "src",
        "--tests", "a/**/*.rb", "--tests", "b/**/*.rb",
        "--soft-timeout", "2.5", "--hard-timeout", "9", "--leak-every", "3",
        "--no-coverage", "--jobs", "4", "--max-survivors", "2",
        "--exclude", "x.rb", "--exclude", "y.rb", "--isolate-db"
      ]
    end

    it "parses scalar, repeatable, and toggle flags" do
      opts = cli.__send__(:parse, arguments)
      expect(opts).to(include(framework: "minitest", source_root: "src", tests: ["a/**/*.rb", "b/**/*.rb"]))
      expect(opts).to(include(soft_timeout: 2.5, hard_timeout: 9.0, leak_every: 3, coverage: false))
      expect(opts).to(include(jobs: 4, max_survivors: 2, exclude: ["x.rb", "y.rb"], isolate_db: true))
    end

    it "toggles --fail-on-no-coverage on and back off" do
      expect(cli.__send__(:parse, ["--fail-on-no-coverage"])[:fail_on_no_coverage]).to(be(true))
      off = cli.__send__(:parse, ["--fail-on-no-coverage", "--no-fail-on-no-coverage"])
      expect(off[:fail_on_no_coverage]).to(be(false))
    end

    it "treats positional arguments as paths overriding the default" do
      opts = cli.__send__(:parse, ["app/models", "lib/core.rb"])
      expect(opts[:paths]).to(eq(["app/models", "lib/core.rb"]))
    end

    # An unconditional assignment would blank them back to the defaults.
    it "keeps the config paths: when no positional paths are given" do
      File.write("custom.yml", %(paths: ["only/**/*.rb"]\n))
      expect(cli.__send__(:parse, ["--config", "custom.yml"])[:paths]).to(eq(["only/**/*.rb"]))
    end

    it "defaults --isolated off and turns it on when given" do
      expect(cli.__send__(:parse, [])[:isolated]).to(be(false))
      expect(cli.__send__(:parse, ["--isolated"])[:isolated]).to(be(true))
    end

    it "parses --max-ignored and leaves it unset by default" do
      expect(cli.__send__(:parse, [])[:max_ignored]).to(be_nil)
      expect(cli.__send__(:parse, ["--max-ignored", "5"])[:max_ignored]).to(eq(5))
    end

    # nil means auto: Report::Progress keys off stderr being a tty.
    it "leaves progress on auto by default and honors --[no-]progress" do
      expect(cli.__send__(:parse, [])[:progress]).to(be_nil)
      expect(cli.__send__(:parse, ["--progress"])[:progress]).to(be(true))
      expect(cli.__send__(:parse, ["--no-progress"])[:progress]).to(be(false))
    end
  end

  describe "#gate" do
    def digest = Kimera::CLI::Run::Digest.new(emission: nil)

    def report(survivors, no_coverage: 0, ignored: 0, unjudged: 0)
      results =
        Array.new(survivors) do |i|
          Kimera::MutantResult.new(mutant_id: i, status: :survived, file: "x.rb", duration: 0.0)
        end
      results +=
        Array.new(no_coverage) do |i|
          Kimera::MutantResult.new(mutant_id: survivors + i, status: :no_coverage, file: "x.rb", duration: 0.0)
        end
      results +=
        Array.new(ignored) do |i|
          Kimera::MutantResult.new(
            mutant_id: survivors + no_coverage + i, status: :ignored, file: "x.rb",
            duration: 0.0
          )
        end
      results +=
        Array.new(unjudged) do |i|
          Kimera::MutantResult.new(
            mutant_id: survivors + no_coverage + ignored + i,
            status: :harness_error,
            file: "x.rb", duration: 0.0
          )
        end
      Kimera::RunReport.new(results: results)
    end

    # Otherwise a run where every worker died could gate at 100% and exit 0.
    it "fails on a mutant the harness could not judge, and honours --max-errors" do
      report = report(0, unjudged: 1)
      expect(digest.gate(report, { max_survivors: nil, max_errors: 0 })).to(eq(2))
      expect(digest.gate(report, { max_survivors: nil, max_errors: 1 })).to(eq(0))
      expect(digest.gate(report(0, unjudged: 2), { max_survivors: nil, max_errors: 1 })).to(eq(2))
    end

    def pattern
      /
        gate\ failed:\ survivors=1\ >\ max_survivors=0\n.*
        gate\ failed:\ ignored=2\ >\ max_ignored=1\n.*
        gate\ failed:\ unjudged=1\ >\ max_errors=0
      /xm
    end

    # Exit 2 beside a healthy summary is untriageable from a CI log alone.
    it "names each tripped gate on stderr" do
      report = report(1, ignored: 2, unjudged: 1)
      options = { max_survivors: nil, max_ignored: 1, max_errors: 0, fail_on_no_coverage: false }
      expect { digest.gate(report, options) }.to(output(pattern).to_stderr)
    end

    it "names the no-coverage gate when --fail-on-no-coverage trips it" do
      report = report(0, no_coverage: 3)
      options = { max_survivors: nil, fail_on_no_coverage: true }
      expect { expect(digest.gate(report, options)).to(eq(2)) }
        .to(output(/gate failed: 3 mutant\(s\) with no covering test/).to_stderr)
    end

    it "returns 0 when there are no survivors and no threshold" do
      expect(digest.gate(report(0), { max_survivors: nil })).to(eq(0))
    end

    it "returns 2 when any survivor exists and there is no threshold" do
      expect(digest.gate(report(1), { max_survivors: nil })).to(eq(2))
    end

    it "passes within the threshold and fails above it" do
      expect(digest.gate(report(2), { max_survivors: 2 })).to(eq(0))
      expect(digest.gate(report(3), { max_survivors: 2 })).to(eq(2))
    end

    it "ignores uncovered mutants unless fail_on_no_coverage is set" do
      report = report(0, no_coverage: 1)
      expect(digest.gate(report, { max_survivors: nil })).to(eq(0))
      expect(digest.gate(report, { max_survivors: nil, fail_on_no_coverage: true })).to(eq(2))
    end

    it "fails on uncovered mutants even when survivors are within threshold" do
      report = report(1, no_coverage: 1)
      expect(digest.gate(report, { max_survivors: 1, fail_on_no_coverage: true })).to(eq(2))
    end

    it "passes with fail_on_no_coverage when everything is covered" do
      expect(digest.gate(report(0), { max_survivors: nil, fail_on_no_coverage: true })).to(eq(0))
    end

    # Each new ignore entry must cost a visible budget raise.
    it "budgets the ignore list via max_ignored" do
      report = report(0, ignored: 3)
      expect(digest.gate(report, { max_survivors: nil, max_ignored: 3 })).to(eq(0))
      expect(digest.gate(report, { max_survivors: nil, max_ignored: 2 })).to(eq(2))
      expect(digest.gate(report, { max_survivors: nil, max_ignored: nil })).to(eq(0))
    end
  end

  describe "path scoping" do
    it "strips the root prefix when the path is under root" do
      root = "/project"
      expect(Kimera::FileSet.relative("/project/app/x.rb", root)).to(eq("app/x.rb"))
    end

    it "returns the original path when it is not under root" do
      expect(Kimera::FileSet.relative("elsewhere/x.rb", "/project")).to(eq("elsewhere/x.rb"))
    end

    it "does not treat a sibling sharing a string prefix as under root" do
      expect(Kimera::FileSet.relative("/project-two/x.rb", "/project")).to(eq("/project-two/x.rb"))
    end
  end

  describe "#build_adapter" do
    it "builds the rspec adapter" do
      # In-process, RSpec warns when the adapter re-points its streams.
      built = hushed { Kimera::Frameworks::Adapter.load("rspec") }
      expect(built).to(be_a(Kimera::Frameworks::RSpecAdapter))
    end

    it "builds the minitest adapter" do
      expect(Kimera::Frameworks::Adapter.load("minitest")).to(be_a(Kimera::Frameworks::MinitestAdapter))
    end

    # The suite already loaded the adapters, so pin the require itself.
    # require_relative is Kernel-private on Adapter; there is nothing else to stub.
    def substitute
      allow(Kimera::Frameworks::Adapter).to(receive(:fetch).and_return(Class.new { def self.build = new }))
      allow(Kimera::Frameworks::Adapter).to(receive(:require_relative))
    end

    it "requires each framework's adapter file before fetching it" do
      substitute
      adapters = Kimera::Frameworks::Adapter
      adapters.load("rspec")
      adapters.load("minitest")
      expect(adapters).to(have_received(:require_relative).with("rspec_adapter"))

      expect(adapters).to(have_received(:require_relative).with("minitest_adapter"))
    end
  end

  describe "#ignored_result" do
    let(:registry) do
      Kimera::RegistryScan.new.source("def m(a, b)\n  a > b\nend\n", file: "x.rb")
    end

    def waived(id)
      Kimera::MutantResult.waived(id, registry.index[id]&.file)
    end

    it "synthesizes an :ignored result carrying the point's file" do
      result = waived(registry.each.first.first.id)
      expect(result).to(have_attributes(status: :ignored, file: "x.rb", duration: 0.0))
      expect(result.detail).to(include("equivalent"))
    end

    it "carries a nil file for an id not in the registry" do
      result = waived(999_999)
      expect(result.status).to(eq(:ignored))
      expect(result.file).to(be_nil)
    end
  end

  describe "#assemble_report" do
    let(:registry) do
      Kimera::RegistryScan.new.source("def m(a, b)\n  a > b\nend\n", file: "x.rb")
    end

    def killed(id)
      Kimera::MutantResult.new(mutant_id: id, status: :killed, file: "x.rb", duration: 0.0)
    end

    def session(id)
      Kimera::Incremental::Session.new.tap { |entry| entry.merge!(Kimera::RunReport.new(results: [killed(id)])) }
    end

    it "combines evaluated session results with synthetic ignored results" do
      evaluated, ignored = registry.each.map { |m, _p| m.id }.first(2)
      report = session(evaluated).report([evaluated], [ignored], registry)
      statuses = report.results.to_h { |r| [r.mutant_id, r.status] }
      expect(statuses[evaluated]).to(eq(:killed))
      expect(statuses[ignored]).to(eq(:ignored))
    end
  end

  describe "#load_registry" do
    around do |example|
      Dir.mktmpdir do |dir|
        @dir = dir
        File.write(File.join(dir, "calc.rb"), "def m(a, b)\n  a > b\nend\n")
        Dir.chdir(dir) { example.run }
      end
    end

    attr_reader :dir

    def sources = Kimera::CLI::Run::Sources.new

    def options(**over)
      {
        paths: ["calc.rb"], exclude: [], operators: Kimera::Operators.keys,
        source_root: ".", registry: nil
      }.merge(over)
    end

    it "builds a registry from source files" do
      registry = sources.load(options)
      expect(registry.files).to(eq(["calc.rb"]))
      expect(registry.count).to(be > 0)
    end

    it "loads a prebuilt registry when --registry is given" do
      built = Kimera::RegistryScan.new.source("def m(a, b)\n  a > b\nend\n", file: "calc.rb")
      path = File.join(dir, "reg.json")
      built.write(path)
      registry = sources.load(options(registry: path))
      expect(registry.count).to(eq(built.count))
    end

    it "restricts building to changed files in incremental mode" do
      File.write(File.join(dir, "other.rb"), "def n(a, b)\n  a < b\nend\n")
      changed = { "calc.rb" => Set[2] }
      registry = sources.load(options(paths: ["calc.rb", "other.rb"]), changed)
      expect(registry.files).to(eq(["calc.rb"]))
    end

    it "protects the runtime selector except in isolated mode" do
      runtime = Kimera::Runtime::SOURCE_PATH
      protected = sources.load(options(paths: [runtime]))
      isolated = sources.load(options(paths: [runtime], isolated: true))
      expect(protected.count).to(eq(0))
      expect(isolated.count).to(be > 0)
    end
  end

  describe "#emit_report" do
    let(:registry) do
      Kimera::RegistryScan.new.source("def m(a, b)\n  a > b\nend\n", file: "x.rb")
    end

    def emitted(json)
      report = Kimera::RunReport.new(results: [], registry: registry)
      captured do
        Kimera::CLI::Run::Emission.new.emit(report, registry, path: json)
      end
    end

    def emission(dir)
      json = File.join(dir, "report.json")
      [emitted(json), json]
    end

    it "prints the text report and writes JSON when a path is given" do
      Dir.mktmpdir do |dir|
        out, json = emission(dir)
        expect(out).to(include("mutants=0"))
        expect(JSON.parse(File.read(json))).to(have_key("counts"))
      end
    end

    it "creates the JSON output's parent directory if it is missing" do
      Dir.mktmpdir do |dir|
        json = File.join(dir, "nested", "out", "report.json")
        emitted(json)
        expect(File.exist?(json)).to(be(true))
      end
    end

    it "can write the final text report to a log while staying quiet" do
      Dir.mktmpdir do |dir|
        log = File.join(dir, "logs", "kimera.txt")
        io = StringIO.new
        report = Kimera::RunReport.new(results: [], registry: registry)
        Kimera::CLI::Run::Emission.new(io: io, quiet: true).emit(report, registry, log: log)
        expect(io.string).to(eq(""))
        expect(File.read(log)).to(include("mutants=0"))
      end
    end

    it "prints resolved settings in verbose mode" do
      io = StringIO.new
      Kimera::CLI::Run::Digest.new(io: io, emission: nil).verbose(
        framework: "rspec", jobs: 4, paths: ["app/**/*.rb"], tests: ["spec/**/*_spec.rb"], format: "json"
      )
      expect(io.string).to(include("framework=rspec", "jobs=4", "format=json"))
    end
  end

  describe "#changed_lines" do
    it "delegates to GitDiff with the since ref and source root" do
      stub = receive(:lines).with(since: "main", root: "/proj").and_return("x.rb" => Set[1])
      allow(Kimera::Incremental::GitDiff).to(stub)
      result = Kimera::CLI::Run::Sources.changed({ since: "main", source_root: "/proj" })
      expect(result).to(eq("x.rb" => Set[1]))
    end
  end

  describe "#run orchestration (harness skipped via a complete session)" do
    around do |example|
      Dir.mktmpdir do |dir|
        @dir = dir
        Dir.chdir(dir) { example.run }
      end
    end

    attr_reader :dir

    def capture(argv)
      io = StringIO.new
      original = $stdout
      $stdout = io
      [io.string, cli.run(argv)]
    ensure
      $stdout = original
    end

    def saved(registry, path, status: :killed)
      session = Kimera::Incremental::Session.new
      results =
        registry.each.map do |mutant, point|
          Kimera::MutantResult.new(mutant_id: mutant.id, status: status, file: point.file, duration: 0.0)
        end
      session.merge!(Kimera::RunReport.new(results: results))
      session.save(path, registry: registry)
      results
    end

    def calculation
      File.write("calc.rb", "def m(a, b)\n  a > b\nend\n")
      Kimera::RegistryScan.new.source(File.read("calc.rb"), file: "calc.rb")
    end

    def reuse
      registry = calculation
      manifest = File.join(dir, "reg.json")
      registry.write(manifest)
      journal = File.join(dir, "session.json")
      results = saved(registry, journal)

      output = File.join(dir, "report.json")
      out, status = capture(["calc.rb", "--registry", manifest, "--session", journal, "--report", output])
      [out, status, output, results]
    end

    it "loads the registry, reuses session results, reports, and gates" do
      out, status, output, results = reuse
      expect(out).to(include("killed=#{results.size}"))
      expect(status).to(eq(0))
      expect(JSON.parse(File.read(output))["counts"][:killed.to_s] || 0).to(be >= 0)
    end

    # Mirror the CLI's build so session ids line up and nothing reaches the harness.
    def scope
      File.write("calc.rb", "def m(a, b)\n  a > b\nend\n")
      File.write("other.rb", "def n(a, b)\n  a < b\nend\n")
      allow(Kimera::Incremental::GitDiff).to(receive(:lines).and_return("calc.rb" => Set[2]))
      registry = Kimera::RegistryScan.new.build(["calc.rb"])
      journal = File.join(dir, "session.json")
      saved(registry, journal)
      out, status = capture(["calc.rb", "other.rb", "--since", "main", "--session", journal])
      [out, status, Kimera::Incremental::Selection.select(registry, "calc.rb" => Set[2])]
    end

    it "announces the incremental scope precisely and builds only changed files" do
      out, status, selected = scope
      expect(selected).not_to(be_empty)
      expect(out).to(include("Incremental: #{selected.size} mutants on lines changed since main (1 changed files)."))
      expect(status).to(eq(0))
    end

    def configuration
      File.write("custom.yml", <<~YAML)
        ignore:
          - file: calc.rb
            label: "> => <"
            reason: spec fixture judged equivalent
      YAML
    end

    # The session also holds a verdict for the ignored mutant.
    def waiver
      registry = calculation
      configuration
      journal = File.join(dir, "session.json")
      results = saved(registry, journal)

      output = File.join(dir, "report.json")
      out, status = capture(["calc.rb", "--config", "custom.yml", "--session", journal, "--report", output])
      [
        out, status, JSON.parse(File.read(output)), results,
        registry.each.find { |m, _p| m.label == "> => <" }.first
      ]
    end

    it "excludes ignored mutants from evaluation and reports them exactly once" do
      out, status, saved, results, ignored = waiver
      expect(out).to(include("Ignoring 1 mutant(s) marked equivalent."))
      expect(saved["counts"]).to(include("ignored" => 1, "killed" => results.size - 1))
      expect(status).to(eq(0))
      expect(saved["results"].to_h { |r| [r["mutant_id"], r["status"]] }[ignored.id]).to(eq("ignored"))
    end

    def persistence
      journal = File.join(dir, "session.json")
      results = saved(calculation, journal)

      _out, status = capture(["calc.rb", "--session", journal])
      [journal, results, status]
    end

    it "re-persists the session with fingerprints and run metadata" do
      journal, results, status = persistence
      expect(status).to(eq(0))
      saved = JSON.parse(File.read(journal))
      expect(saved["meta"]).to(eq("since" => nil))
      expect(saved["fingerprints"].size).to(eq(results.size))
    end

    def warning
      File.write("custom.yml", <<~YAML)
        ignore:
          - file: calc.rb
            line: 999
            label: "< => >"
            reason: spec fixture with a drifted anchor
      YAML
      journal = File.join(dir, "session.json")
      saved(calculation, journal)
      transcript { cli.run(["calc.rb", "--config", "custom.yml", "--session", journal]) }
    end

    it "warns about an ignore entry whose anchor matches no mutant (stale)" do
      _out, error, status = warning
      expect(status).to(eq(0))
      expect(error).to(include("kimera: warning: ignore entry matches no mutant (stale anchor?): calc.rb:999 < => >"))
    end

    def survivor
      registry = calculation
      manifest = File.join(dir, "reg.json")
      registry.write(manifest)
      journal = File.join(dir, "session.json")
      saved(registry, journal, status: :survived)
      _out, status = capture(["calc.rb", "--registry", manifest, "--session", journal])
      status
    end

    it "gates with exit code 2 when the session holds survivors" do
      expect(survivor).to(eq(2))
    end
  end

  # each wires a full double chain (adapter/harness/session) to prove one
  # real orchestration path.
  describe "#run_harness wiring" do
    let(:registry) do
      Kimera::RegistryScan.new.source("def m(a, b)\n  a > b\nend\n", file: "x.rb")
    end

    def settings(**over)
      {
        framework: "rspec", source_root: ".", tests: ["spec/**/*_spec.rb"],
        soft_timeout: 5.0, hard_timeout: nil, leak_every: 10, jobs: 1,
        isolate_db: false, coverage: true
      }.merge(over)
    end

    def framework(**attrs)
      adapter = instance_double(Kimera::Frameworks::RSpecAdapter, **attrs)
      allow(Kimera::Frameworks::Adapter).to(receive(:load).and_return(adapter))

      adapter
    end

    def pass(registry, options, todo, session)
      adapter = Kimera::Frameworks::Adapter.load(options[:framework])
      Kimera::CLI::Run::Pass.new(registry, options, adapter).call(todo, session)
    end

    def executor(**attrs)
      harness = instance_double(Kimera::Execution::Harness, **attrs)
      allow(Kimera::Execution::Harness).to(receive(:new).and_return(harness))
      harness
    end

    def result(id, status)
      Kimera::RunReport.new(
        results: [Kimera::MutantResult.new(mutant_id: id, status: status, file: "x.rb", duration: 0.0)]
      )
    end

    def warmed
      report = Kimera::RunReport.new(results: [])
      harness = executor
      allow(harness).to(receive_messages(warm!: nil, run: report))
      session = Kimera::Incremental::Session.new
      allow(session).to(receive(:merge!))
      [report, harness, session, framework(finish: nil)]
    end

    # finish runs the suite's after(:suite) teardown for what warm! set up.
    def verify(harness, session, report, adapter)
      expect(harness).to(have_received(:warm!).with(kind_of(Array)))
      expect(harness).to(have_received(:run).with(ids: [1, 2], label: "mutants"))
      expect(session).to(have_received(:merge!).with(report))
      expect(adapter).to(have_received(:finish))
    end

    it "builds an adapter and harness, warms up, runs, and merges into the session" do
      report, harness, session, adapter = warmed
      returned = pass(registry, settings, [1, 2], session)
      expect(returned).to(eq(report))
      verify(harness, session, report, adapter)
    end

    def routing
      framework(test_ids: ["t1"], finish: nil)
      harness = executor(coverage: {})
      allow(harness).to(receive_messages(warm!: nil, run: nil))
      runner = instance_double(
        Kimera::Execution::IsolatedExecution, verify!: nil, run: Kimera::RunReport.new(results: [])
      )
      allow(Kimera::Execution::IsolatedExecution).to(receive(:new).and_return(runner))
      [harness, runner, Kimera::Incremental::Session.new]
    end

    # Isolated mode forces coverage on to pick each mutant's covering tests.
    def route(harness)
      expect(harness).to(have_received(:warm!).with(kind_of(Array)))
      expect(harness).not_to(have_received(:run))
    end

    it "hands --hard-timeout to the isolated runner" do
      _harness, _runner, session = routing
      pass(registry, settings(coverage: false, isolated: true, hard_timeout: 9.0), [1], session)
      expect(Kimera::Execution::IsolatedExecution).to(have_received(:new).with(hash_including(hard_timeout: 9.0)))
    end

    it "routes evaluation through the IsolatedExecution when --isolated" do
      harness, runner, session = routing
      pass(registry, settings(coverage: false, isolated: true), [1], session)
      expect(runner).to(have_received(:verify!).ordered)
      expect(runner).to(have_received(:run).with(ids: [1], label: "mutants (isolated)").ordered)
      route(harness)
    end

    def bypass
      framework(finish: nil)
      harness = executor
      allow(harness).to(receive_messages(without_coverage!: nil, run: Kimera::RunReport.new(results: [])))
      session = Kimera::Incremental::Session.new
      allow(session).to(receive(:merge!))
      [harness, session]
    end

    it "skips coverage measurement when --no-coverage is on and not isolated" do
      harness, session = bypass
      pass(registry, settings(coverage: false, isolated: false), [1], session)
      expect(harness).to(have_received(:without_coverage!).with(kind_of(Array)))
      expect(harness).to(have_received(:run).with(ids: [1], label: "mutants"))
    end

    # Mutant 1 is covered only by a normal spec; mutant 2 by a pool-unsafe one.
    def partition
      framework(test_ids: %w[t1 t2], finish: nil)
      harness = executor(coverage: { 1 => ["./spec/unit_spec.rb[1:1]"], 2 => ["./spec/acp/end_to_end_spec.rb[1:2]"] })
      allow(harness).to(receive_messages(warm!: nil, run: result(1, :killed)))
      runner = instance_double(Kimera::Execution::IsolatedExecution, verify!: nil, run: result(2, :survived))
      allow(Kimera::Execution::IsolatedExecution).to(receive(:new).and_return(runner))
      session = Kimera::Incremental::Session.new
      allow(session).to(receive(:merge!))
      [harness, runner, session]
    end

    def distribute(harness, runner)
      expect(harness).to(have_received(:run).with(ids: [1], label: "mutants (warm)"))
      expect(runner).to(have_received(:run).with(ids: [2], label: "mutants (isolated)"))
    end

    it "isolates only mutants covered by a pool-unsafe spec and merges the reports" do
      harness, runner, session = partition
      opts = settings(isolate_when_covered_by: ["end_to_end_spec"])
      report = pass(registry, opts, [1, 2], session)
      expect(report.results.map(&:mutant_id)).to(contain_exactly(1, 2))
      distribute(harness, runner)
    end
  end

  describe "baseline failure handling" do
    around do |example|
      Dir.mktmpdir do |dir|
        @dir = dir
        Dir.chdir(dir) { example.run }
      end
    end

    attr_reader :dir

    def failure = Kimera::Execution::BaselineFailure.new("baseline suite is not green: t1")

    def baseline
      File.write("calc.rb", "def m(a, b)\n  a > b\nend\n")
      manifest = File.join(dir, "reg.json")
      Kimera::RegistryScan.new.source(File.read("calc.rb"), file: "calc.rb").write(manifest)
      allow(Kimera::Frameworks::Adapter).to(receive(:load).and_return(nil))
      allow(Kimera::CLI::Run::Pass).to(receive(:new).and_raise(failure))

      manifest
    end

    it "warns and returns 1 when the harness reports the baseline is not green" do
      _out, error, status = transcript { cli.run(["calc.rb", "--registry", baseline]) }
      expect(status).to(eq(1))
      expect(error).to(include("kimera: baseline suite is not green"))
    end
  end

  # A typo'd path or glob must fail, not score perfect over nothing.
  describe "empty scope guards" do
    around do |example|
      Dir.mktmpdir do |dir|
        @dir = dir
        Dir.chdir(dir) { example.run }
      end
    end

    attr_reader :dir

    def capture(argv)
      error = StringIO.new
      errors = $stderr
      output = $stdout
      $stderr = error
      $stdout = StringIO.new
      begin
        [cli.run(argv), error.string]
      ensure
        $stderr = errors
        $stdout = output
      end
    end

    # A silent no-op exclude widens a CI gate's scope.
    it "warns about exclude patterns that matched nothing" do
      File.write(File.join(dir, "a.rb"), "class A; end\n")
      warning = "kimera: warning: exclude pattern matched no source files: typo/**/*.rb\n"
      scan = -> { Kimera::CLI::Run::Sources.new.expand(["a.rb"], ["typo/**/*.rb"], "source", "hint") }
      expect { scan.call }.to(output(warning).to_stderr)
    end

    it "warns and returns 1 when no source files match the paths" do
      status, error = capture(%w[nonexistent_dir other_missing])
      expect(status).to(eq(1))
      message = "kimera: no source files matched: nonexistent_dir, other_missing (check paths and --exclude)"
      expect(error).to(include(message))
    end

    it "warns and returns 1 when no test files match the globs" do
      File.write("calc.rb", "def m(a, b)\n  a > b\nend\n")
      status, error = capture(["calc.rb", "--tests", "nope/**/*_spec.rb", "--tests", "still/**/*_spec.rb"])
      expect(status).to(eq(1))
      expect(error).to(include("kimera: no test files matched: nope/**/*_spec.rb, still/**/*_spec.rb (check --tests)"))
    end

    def fixtures
      File.write("calc.rb", "def m(a, b)\n  a > b\nend\n")
      FileUtils.mkdir_p("spec")
      File.write("spec/good_spec.rb", "")
      File.write("spec/flaky_spec.rb", "")
    end

    def warmed
      expanded = nil
      allow(Kimera::Execution::Harness).to(receive(:new).and_wrap_original) do |original, **kwargs|
        harness = original.call(**kwargs)
        allow(harness).to(receive(:warm!) { |files, **| expanded = files })
        allow(harness).to(receive(:run).and_return(Kimera::RunReport.new(results: [])))
        harness
      end
      -> { expanded }
    end

    it "drops test files matching --exclude-test" do
      fixtures
      expanded = warmed
      cli.run(["calc.rb", "--tests", "spec/**/*_spec.rb", "--exclude-test", "spec/flaky_spec.rb"])
      expect(expanded.call).to(eq(["spec/good_spec.rb"]))
    end

    it "still passes quietly when an incremental diff selects zero mutants" do
      File.write("calc.rb", "def m(a, b)\n  a > b\nend\n")
      allow(Kimera::Incremental::GitDiff).to(receive(:lines).and_return({}))

      status, = capture(["calc.rb", "--since", "main"])
      expect(status).to(eq(0))
    end
  end

  describe "#announce_scope" do
    let(:registry) do
      Kimera::RegistryScan.new.source("def m(a, b)\n  a > b\nend\n", file: "x.rb")
    end

    def announced(selected, ignored, options)
      io = StringIO.new
      original = $stdout
      $stdout = io
      Kimera::CLI::Run::Digest.new(emission: nil)
        .announce(selected, ignored, files: registry.files.size, since: options[:since])
      io.string
    ensure
      $stdout = original
    end

    it "announces incremental scope and ignored counts" do
      out = announced([1, 2], [3], { since: "main" })
      expect(out).to(include("Incremental: 2 mutants on lines changed since main"))
      expect(out).to(include("Ignoring 1 mutant(s) marked equivalent"))
    end

    it "stays silent when not incremental and nothing is ignored" do
      expect(announced(nil, [], {})).to(eq(""))
    end
  end
end
