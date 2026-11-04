# frozen_string_literal: true

require "kimera/cli/run"
require "kimera/frameworks/rspec_suite"
require "kimera/registry/builder"
require "stringio"
require "tmpdir"

using ResultFields

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
    status = ended(yield, out, error)

    [out.string, error.string, status]
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
        operators: Kimera::Operators.build.map(&:key),
        soft_timeout: 5.0, hard_timeout: nil,
        relative_timeout: true, timeout_factor: nil, timeout_slack: nil,
        registry: nil, report: "tmp/kimera/report.json", format: "text", focus: [], gate: true, coverage: true,
        require: [],
        since: nil, session: nil, max_survivors: nil, max_ignored: nil,
        max_errors: 0, evaluate_ignored: false, baseline: nil,
        jobs: 1, exclude: [], exclude_tests: [], exclude_test_names: [], config: nil, ignore: [],
        isolate_db: false,
        isolated: false, rejudge: true, fail_on_no_coverage: false, count_no_coverage: true,
        judge_isolated_only: nil, confirm_survivors: nil,
        progress: nil, color: nil, quiet: false, verbose: false, log: nil,
        pidfile: nil, summary: nil,
        isolate_when_covered_by: [], methods: [], lines: {},
        paths: ["app/**/*.rb", "lib/**/*.rb"], attribution: "any", unit_tests: {}, seed: nil, flaky_runs: 0,
        test_quality: false, reuse_coverage: false
      }
    end

    def parsed(*arguments) = cli.__send__(:parse, arguments).to_h

    def unit_config = File.write("custom.yml", %(attribution: unit\nunit_tests:\n  "lib/**/*.rb": "t/{name}_t.rb"\n))

    it "reads attribution and unit tests from the config" do
      unit_config
      expect(parsed("--config", "custom.yml").values_at(:attribution, :unit_tests))
        .to(eq(["unit", { "lib/**/*.rb" => ["t/{name}_t.rb"] }]))
    end

    it "lets --attribution and --unit-tests replace the config's rules", :aggregate_failures do
      unit_config
      flagged = parsed("--config", "custom.yml", "--unit-tests", "app/*.rb=u/{name}.rb", "--attribution", "any")
      expect(flagged.values_at(:attribution, :unit_tests)).to(eq(["any", { "app/*.rb" => ["u/{name}.rb"] }]))
      expect(flagged).not_to(have_key(:cli_unit_tests))
    end

    it "reads --seed as a number" do
      expect([%w[--seed 0], %w[--seed 2147483647]].map { |arguments| parsed(*arguments)[:seed] })
        .to(eq([0, 2_147_483_647]))
    end

    it "draws a seed in range for random", :aggregate_failures do
      drawn = Array.new(3) { parsed("--seed", "random")[:seed] }
      expect(drawn).to(all(be_between(0, 2_147_483_647)))
      expect(drawn.uniq.size).to(be > 1)
    end

    it "reads the seed and the rerun count from the config" do
      File.write("custom.yml", "seed: 12\nflaky_runs: 3\n")
      expect(parsed("--config", "custom.yml").values_at(:seed, :flaky_runs)).to(eq([12, 3]))
    end

    it "rejects a seed that is no whole number in range" do
      %w[-1 2147483648 1.5 x].each do |bad|
        expect { cli.__send__(:parse, ["--seed", bad]) }.to(
          raise_error(
            Kimera::UsageError,
            "--seed takes a whole number from 0 to 2147483647, or random; got #{bad.inspect}"
          )
        )
      end
    end

    it "reads --flaky-runs, zero needing no coverage baseline" do
      expect([%w[--flaky-runs 2], %w[--flaky-runs 0 --no-coverage]].map { |arguments| parsed(*arguments)[:flaky_runs] })
        .to(eq([2, 0]))
    end

    it "rejects a rerun count that is no whole number", :aggregate_failures do
      File.write("custom.yml", "flaky_runs: many\n")
      expect { parsed("--config", "custom.yml") }
        .to(raise_error(Kimera::UsageError, '--flaky-runs takes a whole number of reruns, got "many"'))
      expect { parsed("--flaky-runs", "-1") }.to(raise_error(Kimera::UsageError, /--flaky-runs takes/))
    end

    it "rejects reruns without the coverage baseline" do
      expect { parsed("--flaky-runs", "1", "--no-coverage") }
        .to(raise_error(Kimera::UsageError, "--flaky-runs needs the coverage baseline; drop --no-coverage"))
    end

    it "rejects strict attribution without the coverage baseline, and an unknown mode", :aggregate_failures do
      expect { cli.__send__(:parse, %w[--attribution unit --no-coverage]) }
        .to(raise_error(Kimera::UsageError, "--attribution unit needs the coverage baseline; drop --no-coverage"))
      expect(cli.__send__(:parse, %w[--attribution any --no-coverage])[:coverage]).to(be(false))
      expect(cli.__send__(:parse, %w[--attribution unit])[:coverage]).to(be(true))
      expect { cli.__send__(:parse, %w[--attribution all]) }.to(raise_error(Kimera::UsageError, /unknown attribution/))
    end

    # Exact equality, so a dropped or drifted default fails.
    it "applies exactly the documented defaults" do
      expect(cli.__send__(:parse, []).to_h).to(eq(defaults))
    end

    it "reads --max-errors as the unjudged-mutant budget" do
      expect(cli.__send__(:parse, ["--max-errors", "3"])[:max_errors]).to(eq(3))
    end

    it "splits --operators into an array of keys" do
      parsed = cli.__send__(:parse, ["--operators", "comparison,regexp"])
      expect(parsed[:operators]).to(eq(%w[comparison regexp]))
    end

    it "merges config-file defaults, with flags overriding them" do
      File.write("custom.yml", "jobs: 7\nsoft_timeout: 3.5\n")
      parsed = cli.__send__(:parse, ["--config", "custom.yml"])
      expect(parsed[:jobs]).to(eq(7))
      expect(parsed[:soft_timeout]).to(eq(3.5))
      expect(cli.__send__(:parse, ["--config", "custom.yml", "--jobs", "2"])[:jobs]).to(eq(2))
    end

    # Appending would re-include the whole suite when scoping to one file.
    it "replaces the config tests: glob when --tests is given" do
      File.write("custom.yml", %(tests: ["spec/config_spec.rb"]\n))
      parsed = cli.__send__(:parse, ["--config", "custom.yml", "--tests", "spec/only_spec.rb"])
      expect(parsed[:tests]).to(eq(["spec/only_spec.rb"]))
    end

    it "keeps the config tests: glob to tell a narrowed run apart" do
      File.write("custom.yml", %(tests: ["spec/config_spec.rb"]\n))
      parsed = cli.__send__(:parse, ["--config", "custom.yml", "--tests", "spec/only_spec.rb"])
      expect(parsed[:configured_tests]).to(eq(["spec/config_spec.rb"]))
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
        hard-timeout relative-timeout timeout-factor timeout-slack coverage since session max-survivors
        max-ignored fail-on-no-coverage count-no-coverage attribution unit-tests seed flaky-runs test-quality
        jobs progress
        isolate-db isolated
        isolate-when-covered-by rejudge exclude config pidfile evaluate-ignored no-baseline
      ]
    end

    # A flag's help line with its wrapped continuation lines, flag and argument removed.
    def description(lines, index)
      [lines[index], *lines[(index + 1)..].take_while { |l| l !~ /\A\s*--/ }].join.sub(/\A\s*--\S+( \S+)?/, "")
    end

    def document(lines, flag)
      index = lines.index { |l| l =~ /\A\s*--(\[no-\])?#{flag}\b/ }
      expect(index).not_to(be_nil, "--#{flag} missing from --help")
      expect(description(lines, index).scan(/\w/).size).to(be >= 10, "--#{flag} lacks a description")
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
        "--soft-timeout", "2.5", "--hard-timeout", "9",
        "--no-coverage", "--jobs", "4", "--max-survivors", "2",
        "--exclude", "x.rb", "--exclude", "y.rb", "--isolate-db"
      ]
    end

    it "parses scalar, repeatable, and toggle flags" do
      parsed = cli.__send__(:parse, arguments)
      expect(parsed).to(include(framework: "minitest", source_root: "src", tests: ["a/**/*.rb", "b/**/*.rb"]))
      expect(parsed).to(include(soft_timeout: 2.5, hard_timeout: 9.0, coverage: false))
      expect(parsed).to(include(jobs: 4, max_survivors: 2, exclude: ["x.rb", "y.rb"], isolate_db: true))
    end

    it "toggles --fail-on-no-coverage on and back off" do
      expect(cli.__send__(:parse, ["--fail-on-no-coverage"])[:fail_on_no_coverage]).to(be(true))
      off = cli.__send__(:parse, ["--fail-on-no-coverage", "--no-fail-on-no-coverage"])
      expect(off[:fail_on_no_coverage]).to(be(false))
    end

    it "treats positional arguments as paths overriding the default" do
      parsed = cli.__send__(:parse, ["app/models", "lib/core.rb"])
      expect(parsed[:paths]).to(eq(["app/models", "lib/core.rb"]))
    end

    # An unconditional assignment would blank them back to the defaults.
    it "keeps the config paths: when no positional paths are given" do
      File.write("custom.yml", %(paths: ["only/**/*.rb"]\n))
      expect(cli.__send__(:parse, ["--config", "custom.yml"])[:paths]).to(eq(["only/**/*.rb"]))
    end

    it "turns the isolated re-judge off with --no-rejudge or rejudge: false in the config" do
      expect(cli.__send__(:parse, ["--no-rejudge"])[:rejudge]).to(be(false))
      File.write("custom.yml", "rejudge: false\n")
      expect(cli.__send__(:parse, ["--config", "custom.yml"])[:rejudge]).to(be(false))
      expect(cli.__send__(:parse, ["--config", "custom.yml", "--rejudge"])[:rejudge]).to(be(true))
    end

    it "tunes the relative timeout, or turns it off, by flag or config", :aggregate_failures do
      tuned = cli.__send__(:parse, ["--timeout-factor", "4", "--timeout-slack", "0.5"])
      expect(tuned).to(include(timeout_factor: 4.0, timeout_slack: 0.5))
      expect(cli.__send__(:parse, ["--no-relative-timeout"])[:relative_timeout]).to(be(false))
      File.write("custom.yml", "relative_timeout: false\ntimeout_factor: 20\ntimeout_slack: 2.5\n")
      expect(cli.__send__(:parse, ["--config", "custom.yml"]))
        .to(include(relative_timeout: false, timeout_factor: 20, timeout_slack: 2.5))
    end

    it "defaults --isolated off and turns it on when given" do
      expect(cli.__send__(:parse, [])[:isolated]).to(be(false))
      expect(cli.__send__(:parse, ["--isolated"])[:isolated]).to(be(true))
    end

    it "parses --max-ignored and leaves it unset by default" do
      expect(cli.__send__(:parse, [])[:max_ignored]).to(be_nil)
      expect(cli.__send__(:parse, ["--max-ignored", "5"])[:max_ignored]).to(eq(5))
    end

    # nil means auto: Report::Progress draws a bar on a tty and plain lines elsewhere.
    it "leaves progress on auto by default and honors --[no-]progress" do
      expect(cli.__send__(:parse, [])[:progress]).to(be_nil)
      expect(cli.__send__(:parse, ["--progress"])[:progress]).to(be(true))
      expect(cli.__send__(:parse, ["--no-progress"])[:progress]).to(be(false))
    end
  end

  describe "#gate" do
    def alerts = Kimera::CLI::Run::Alerts.new

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
      expect(alerts.gate(report, { max_survivors: nil, max_errors: 0 })).to(eq(2))
      expect(alerts.gate(report, { max_survivors: nil, max_errors: 1 })).to(eq(0))
      expect(alerts.gate(report(0, unjudged: 2), { max_survivors: nil, max_errors: 1 })).to(eq(2))
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
      expect { alerts.gate(report, options) }.to(output(pattern).to_stderr)
    end

    it "gates mutants only other units' tests reach as survivors, and says how many there are", :aggregate_failures do
      unowned = Kimera::MutantResult.new(mutant_id: 99, status: :uncovered_by_unit, file: "x.rb")
      both = Kimera::RunReport.new(results: report(1).to_a + [unowned])
      expect { expect(alerts.gate(both, { max_survivors: 1 })).to(eq(2)) }
        .to(output("kimera: gate failed: survivors=2 (1 uncovered_by_unit) > max_survivors=1\n").to_stderr)
      expect(alerts.gate(both, { max_survivors: 2 })).to(eq(0))
      expect(alerts.gate(Kimera::RunReport.new(results: [unowned]), {})).to(eq(2))
    end

    it "names the no-coverage gate when --fail-on-no-coverage trips it" do
      report = report(0, no_coverage: 3)
      options = { max_survivors: nil, fail_on_no_coverage: true }
      expect { expect(alerts.gate(report, options)).to(eq(2)) }
        .to(output(/gate failed: 3 mutant\(s\) with no covering test/).to_stderr)
    end

    it "returns 0 when there are no survivors and no threshold" do
      expect(alerts.gate(report(0), { max_survivors: nil })).to(eq(0))
    end

    it "returns 2 when any survivor exists and there is no threshold" do
      expect(alerts.gate(report(1), { max_survivors: nil })).to(eq(2))
    end

    it "passes within the threshold and fails above it" do
      expect(alerts.gate(report(2), { max_survivors: 2 })).to(eq(0))
      expect(alerts.gate(report(3), { max_survivors: 2 })).to(eq(2))
    end

    it "ignores uncovered mutants unless fail_on_no_coverage is set" do
      report = report(0, no_coverage: 1)
      expect(alerts.gate(report, { max_survivors: nil })).to(eq(0))
      expect(alerts.gate(report, { max_survivors: nil, fail_on_no_coverage: true })).to(eq(2))
    end

    it "fails on uncovered mutants even when survivors are within threshold" do
      report = report(1, no_coverage: 1)
      expect(alerts.gate(report, { max_survivors: 1, fail_on_no_coverage: true })).to(eq(2))
    end

    it "fails on uncovered mutants under count_no_coverage, naming that setting", :aggregate_failures do
      options = { max_survivors: nil, count_no_coverage: true }
      expect { expect(alerts.gate(report(0, no_coverage: 2), options)).to(eq(2)) }
        .to(output(/gate failed: 2 mutant\(s\) with no covering test \(count_no_coverage\)/).to_stderr)
      expect(alerts.gate(report(0), options)).to(eq(0))
    end

    # A scope that killed nothing while mutants only the isolated tier can
    # judge wait has shown nothing: passing would score untested code as
    # tested. Kills, not evaluations, so a tolerated survivor never turns the
    # gate green.
    it "fails a gate that killed nothing while isolated-only mutants were in scope" do
      unmutatable = [Kimera::MutantResult.new(mutant_id: 2, status: :unmutatable, file: "x.rb")]
      message = /gate failed: 0 of 2 mutants killed: 2 only the isolated tier can judge \(run with --isolated\)/
      expect { expect(alerts.gate(Kimera::RunReport.new(results: waiting + unmutatable), {})).to(eq(2)) }
        .to(output(message).to_stderr)
    end

    it "passes that gate once a mutant was killed, or when the only verdict was ignored" do
      judged = Kimera::RunReport.new(results: waiting + report(0, no_coverage: 0).to_a + [verdict_killed])
      ignored = Kimera::RunReport.new(results: report(0, ignored: 1).to_a)
      expect([judged, ignored].map { |run| alerts.gate(run, {}) }).to(eq([0, 0]))
    end

    it "keeps that gate shut for a tolerated survivor" do
      tolerated = Kimera::RunReport.new(results: waiting + report(1, no_coverage: 0).to_a)
      expect(alerts.gate(tolerated, { max_survivors: 1 })).to(eq(2))
    end

    def waiting = [Kimera::MutantResult.new(mutant_id: 1, status: :isolated_only, file: "x.rb")]

    def verdict_killed = Kimera::MutantResult.new(mutant_id: 9, status: :killed, file: "x.rb")

    it "passes with fail_on_no_coverage when everything is covered" do
      expect(alerts.gate(report(0), { max_survivors: nil, fail_on_no_coverage: true })).to(eq(0))
    end

    # Each new ignore entry must cost a visible budget raise.
    it "budgets the ignore list via max_ignored" do
      report = report(0, ignored: 3)
      expect(alerts.gate(report, { max_survivors: nil, max_ignored: 3 })).to(eq(0))
      expect(alerts.gate(report, { max_survivors: nil, max_ignored: 2 })).to(eq(2))
      expect(alerts.gate(report, { max_survivors: nil, max_ignored: nil })).to(eq(0))
    end
  end

  describe "path scoping" do
    it "strips the root prefix when the path is under root" do
      root = "/project"
      expect(Kimera::FileSet::Root.new(root).relative("/project/app/x.rb")).to(eq("app/x.rb"))
    end

    it "returns the original path when it is not under root" do
      expect(Kimera::FileSet::Root.new("/project").relative("elsewhere/x.rb")).to(eq("elsewhere/x.rb"))
    end

    it "does not treat a sibling sharing a string prefix as under root" do
      expect(Kimera::FileSet::Root.new("/project").relative("/project-two/x.rb")).to(eq("/project-two/x.rb"))
    end
  end

  describe "framework suites" do
    it "builds the RSpec suite" do
      # In-process, RSpec warns when the suite re-points its streams.
      built = hushed { Kimera::Frameworks::SuiteRegistry.new.load("rspec") }
      expect(built).to(be_a(Kimera::Frameworks::RSpecSuite))
    end

    it "builds the Minitest suite" do
      expect(Kimera::Frameworks::SuiteRegistry.new.load("minitest")).to(be_a(Kimera::Frameworks::MinitestSuite))
    end

    # The spec run already loaded the suites, so a fresh process, which has
    # not, shows the registry loading each framework's file before it builds
    # the suite the file defines.
    def fresh
      fresh_lines(<<~RUBY)
        require "kimera/frameworks/suite"
        %w[rspec minitest].each { puts Kimera::Frameworks::SuiteRegistry.new.load(it).class }
      RUBY
    end

    it "loads each framework's suite file before fetching its suite" do
      expect(fresh).to(eq(%w[Kimera::Frameworks::RSpecSuite Kimera::Frameworks::MinitestSuite]))
    end
  end

  describe "#ignored_result" do
    let(:registry) do
      Kimera::RegistryScan.new.source("def m(a, b)\n  a > b\nend\n", file: "x.rb")
    end

    def waived(id)
      Kimera::MutantResult.from_waiver(id, registry.index[id]&.file)
    end

    it "synthesizes an :ignored result carrying the point's file" do
      result = waived(registry.each.first.first.id)
      expect(result).to(have_fields(status: :ignored, file: "x.rb", duration: 0.0))
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
      Kimera::Incremental::Session.new.judged([id]) { Kimera::RunReport.new(results: [killed(id)]) }
    end

    it "combines evaluated session results with synthetic ignored results" do
      evaluated, ignored = registry.each.map { |m, _p| m.id }.first(2)
      report = session(evaluated).report([evaluated], [ignored], registry)
      statuses = report.to_a.to_h { |r| [r.mutant_id, r.status] }
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
      Kimera::CLI::Run::Settings.new(
        {
          paths: ["calc.rb"], exclude: [], operators: Kimera::Operators::CATALOG.keys,
          source_root: ".", registry: nil
        }.merge(over)
      )
    end

    it "names the files relative to the source root" do
      FileUtils.mkdir_p(File.join(dir, "sub"))
      File.write(File.join(dir, "sub", "calc.rb"), "def m(a, b)\n  a > b\nend\n")
      expect(sources.load(options(paths: ["sub/calc.rb"], source_root: "sub")).files).to(eq(["calc.rb"]))
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
      changed = Kimera::Incremental::Selection.new({ "calc.rb" => Set[2] }, "main")
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
        Kimera::CLI::Run::Emission.new.emit(report, registry, delivery(path: json))
      end
    end

    def emission(dir)
      json = File.join(dir, "report.json")
      [emitted(json), json]
    end

    it "prints the hints of an unsaved report when no path is given" do
      survived = Kimera::MutantResult.new(mutant_id: registry.each.first.first.id, status: :survived, file: "x.rb")
      report = Kimera::RunReport.new(results: [survived], registry: registry)
      out = captured { Kimera::CLI::Run::Emission.new.emit(report, registry, delivery(format: "text")) }
      expect(out).to(include("run without --no-report to save one"))
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

    # What a quiet emission prints while it writes the text report to the log.
    def quietly_logged(log)
      io = StringIO.new
      report = Kimera::RunReport.new(results: [], registry: registry)
      Kimera::CLI::Run::Emission.new(io: io, quiet: true).emit(report, registry, delivery(log: log))
      io.string
    end

    it "can write the final text report to a log while staying quiet", :aggregate_failures do
      Dir.mktmpdir do |dir|
        log = File.join(dir, "logs", "kimera.txt")
        expect(quietly_logged(log)).to(eq(""))
        expect(File.read(log)).to(include("mutants=0"))
      end
    end

    it "prints resolved settings in verbose mode" do
      io = StringIO.new
      Kimera::CLI::Run::Digest.new(io: io, emission: nil).verbose(
        Kimera::CLI::Run::Settings.new(
          framework: "rspec", jobs: 4, paths: ["app/**/*.rb"], tests: ["spec/**/*_spec.rb"], format: "json"
        )
      )
      expect(io.string).to(include("framework=rspec", "jobs=4", "format=json"))
    end
  end

  describe "#run orchestration (harness skipped via a complete session)" do
    # A --since run finds line 2 of calc.rb changed.
    subject(:cli) { described_class.new(bench: FakeBench.new(changed: { "calc.rb" => Set[2] })) }

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
      [io.string, ended(cli.run(argv), io, $stderr)]
    ensure
      $stdout = original
    end

    # What the CLI stamps a session with when no flag changes the settings.
    def stamp(registry)
      settings = Kimera::CLI::Run::Arguments.new.parse([]).to_h.slice(*Kimera::CLI::Run::Cycle::SETTINGS, :require)
      Kimera::Incremental::Stamp.new(root: ".", sources: registry.files, settings: settings).to_s
    end

    def saved(registry, path, status: :killed)
      results =
        registry.each.map do |mutant, point|
          Kimera::MutantResult.new(mutant_id: mutant.id, status: status, file: point.file, duration: 0.0)
        end
      Kimera::Incremental::Session.new(meta: { "stamp" => stamp(registry) })
        .judged(results.map(&:mutant_id)) { Kimera::RunReport.new(results: results) }.save(path, registry)
      results
    end

    def calculation
      File.write("calc.rb", "def m(a, b)\n  a > b\nend\n")
      Kimera::RegistryScan.new.source(File.read("calc.rb"), file: "calc.rb")
    end

    def reuse(*flags)
      registry = calculation
      manifest = File.join(dir, "reg.json")
      registry.write(manifest)
      journal = File.join(dir, "session.json")
      results = saved(registry, journal)

      output = File.join(dir, "report.json")
      out, status = capture(["calc.rb", "--registry", manifest, "--session", journal, "--report", output, *flags])
      [out, status, output, results]
    end

    # How many workers run a session doesn't change what they judge.
    it "reuses the session at another --jobs" do
      out, _status, _output, results = reuse("--jobs", "3")
      expect(out).to(include("killed=#{results.size}"))
    end

    it "loads the registry, reuses session results, reports, and gates" do
      out, status, output, results = reuse
      expect(out).to(include("killed=#{results.size}"))
      expect(status).to(eq(0))
      expect(JSON.parse(File.read(output))["counts"][:killed.to_s] || 0).to(be >= 0)
    end

    # Mirror the CLI's build so session ids line up and nothing reaches the harness.
    def changed_source
      File.write("calc.rb", "def m(a, b)\n  a > b\nend\n")
      File.write("other.rb", "def n(a, b)\n  a < b\nend\n")
    end

    def scope
      changed_source
      registry = Kimera::RegistryScan.new.build(["calc.rb"])
      journal = File.join(dir, "session.json")
      saved(registry, journal)
      out, status = capture(["calc.rb", "other.rb", "--since", "main", "--session", journal])
      [out, status, Kimera::Incremental::Selection.new({ "calc.rb" => Set[2] }, "main").ids(registry)]
    end

    def unmutated(*flags)
      File.write("calc.rb", "def m(a, b)\n  a > b\nend\n\nPOSITIVE = [1].select { |x| x > 0 }\n")
      journal = File.join(dir, "session.json")
      saved(Kimera::RegistryScan.new.build(["calc.rb"]), journal)
      capture(["calc.rb", "--session", journal, *flags]).first
    end

    it "lists the code it leaves unmutated" do
      expect(unmutated).to(include("Not mutated (1 region(s)):", "calc.rb:5"))
    end

    it "lists unmutated code in an incremental run only where the diff reaches it" do
      out = unmutated("--since", "main")
      expect([out.include?("Incremental:"), out.include?("Not mutated")]).to(eq([true, false]))
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
      expect(saved["meta"]).to(eq("since" => nil, "stamp" => stamp(calculation)))
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

  # Each drives one orchestration path of a pass through fakes of the suite,
  # the warm harness and the isolated tier.
  describe "#run_harness wiring" do
    let(:registry) do
      Kimera::RegistryScan.new.source("def m(a, b)\n  a > b\nend\n", file: "x.rb")
    end

    def settings(**over)
      {
        framework: "rspec", source_root: ".", tests: ["spec/**/*_spec.rb"],
        soft_timeout: 5.0, hard_timeout: nil, jobs: 1,
        isolate_db: false, coverage: true
      }.merge(over)
    end

    def pass(registry, options, todo, harness: FakeHarness.new, suite: FakeSuite.new(["t1"]))
      Kimera::CLI::Run::Pass.new(registry, options, suite, FakeBench.new(harness: harness)).call(todo)
    end

    def result(id, status)
      Kimera::RunReport.new(
        results: [Kimera::MutantResult.new(mutant_id: id, status: status, file: "x.rb", duration: 0.0)]
      )
    end

    def verdict(id, status) = result(id, status).to_a.first

    def both = FakeSuite.new(%w[t1 t2])

    # finish runs the suite's after(:suite) teardown for what warm! set up.
    it "builds an adapter and harness, warms up, and runs" do
      suite = FakeSuite.new
      harness = FakeHarness.new(result(1, :killed))
      returned = pass(registry, settings, [1, 2], harness: harness, suite: suite)
      expect([returned.to_a.map(&:mutant_id), suite.finished?]).to(eq([[1], true]))
      expect(harness.asked).to(match([[:warm!, kind_of(Array), [1, 2]], [:run, [1, 2], "mutants"]]))
    end

    it "names the tests the verdicts cite, from the adapter" do
      named = { "t1" => { "name" => "M compares", "location" => "spec/m_spec.rb:3" } }
      cited = Kimera::RunReport.new(results: [verdict(1, :killed).with(killing_tests: ["t1"])])
      suite = FakeSuite.new(%w[t1 t2], catalog: named.merge("t2" => { "name" => "M cites nothing" }))
      expect(pass(registry, settings, [1, 2], harness: FakeHarness.new(cited), suite: suite).notes.to_h["tests"]).to(eq(named))
    end

    def routing
      isolation = FakeIsolation.new
      [FakeHarness.new(coverage: {}, isolation: isolation), isolation]
    end

    # The test file of each of three tests: the unit's own, the same by its
    # absolute path, and another unit's.
    def unit_files
      { "own" => "./spec/x_spec.rb", "absolute" => File.expand_path("spec/x_spec.rb"), "other" => "spec/other_spec.rb" }
    end

    # A screen that keeps the unit's own tests, by either path, and drops the other.
    def screening
      satisfy { |filter| [screens?(filter), filter.keep("x.rb", %w[own absolute other])] == [true, %w[own absolute]] }
    end

    it "hands the warm harness and the isolated tier one screen of the unit's own tests under --attribution unit" do
      harness = FakeHarness.new
      unit = settings(attribution: "unit", unit_tests: { "x.rb" => ["t/{name}.rb"] })
      pass(registry, unit, [1, 2], harness: harness, suite: FakeSuite.new(files: unit_files))
      expect(harness.settings).to(include(filter: screening))
    end

    it "hands the harness the seed and rerun count, when given" do
      harness = FakeHarness.new
      pass(registry, settings(seed: 7, flaky_runs: 2), [1, 2], harness: harness)
      expect(harness.settings).to(include(seed: 7, flaky_runs: 2))
    end

    def flaky_record = Kimera::Execution::FlakeRecord.new(%w[t9], [3]).tap { |found| found.lose("t9", :timeout, 3) }

    it "reports the flaky tests the warm pass found, naming them from the adapter" do
      harness = FakeHarness.new(flakes: flaky_record)
      suite = FakeSuite.new(catalog: { "t9" => { "name" => "nine" } })
      expect(pass(registry, settings, [1, 2], harness: harness, suite: suite).then { [it.notes.to_h["flaky"], it.notes.to_h["tests"]] })
        .to(eq([flaky_record.to_h, { "t9" => { "name" => "nine" } }]))
    end

    it "hands the harness and the isolated tier test quality, and reports it over the whole suite" do
      harness = FakeHarness.new
      report = pass(registry, settings(test_quality: true), [1, 2], harness: harness, suite: both)
      expect(harness.settings).to(include(test_quality: true))
      expect([report.notes.to_h["suite"], pass(registry, settings, [1, 2], suite: both).notes.to_h["suite"]]).to(eq([%w[t1 t2], nil]))
    end

    it "reports no flaky tests section when none were looked for" do
      expect(pass(registry, settings, [1, 2]).notes.to_h["flaky"]).to(be_nil)
    end

    it "hands the harness an inactive screen by default" do
      harness = FakeHarness.new
      pass(registry, settings(unit_tests: { "x.rb" => ["t"] }), [1, 2], harness: harness)
      expect(harness.settings).to(include(filter: satisfy { |filter| !screens?(filter) }))
    end

    it "hands the relative timeout settings to the warm harness" do
      harness = FakeHarness.new
      timeouts = { relative_timeout: false, timeout_factor: 4.0, timeout_slack: 0.5 }
      pass(registry, settings(**timeouts), [1, 2], harness: harness)
      expect(harness.settings).to(include(timeouts))
    end

    it "hands --hard-timeout to the isolated runner" do
      harness, isolation = routing
      pass(registry, settings(coverage: false, isolated: true, hard_timeout: 9.0), [1], harness: harness)
      expect(isolation.settings).to(include(hard_timeout: 9.0))
    end

    # Isolated mode forces coverage on to pick each mutant's covering tests.
    it "routes evaluation through the IsolatedExecution when --isolated" do
      harness, isolation = routing
      pass(registry, settings(coverage: false, isolated: true), [1], harness: harness)
      expect(isolation.asked).to(eq([[:verify!, [1]], [:run, [1], "mutants (isolated)"]]))
      expect(harness.asked).to(match([[:warm!, kind_of(Array), kind_of(Array)]]))
    end

    it "skips coverage measurement when --no-coverage is on and not isolated" do
      harness = FakeHarness.new
      pass(registry, settings(coverage: false, isolated: false), [1], harness: harness)
      expect(harness.asked).to(match([[:without_coverage!, kind_of(Array)], [:run, [1], "mutants"]]))
    end

    # Mutant 1 is covered only by a normal spec; mutant 2 by a pool-unsafe one.
    def partition
      isolation = FakeIsolation.new(result(2, :survived))
      coverage = { 1 => ["./spec/unit_spec.rb[1:1]"], 2 => ["./spec/acp/end_to_end_spec.rb[1:2]"] }
      [FakeHarness.new(result(1, :killed), coverage: coverage, isolation: isolation), isolation]
    end

    def distribute(harness, isolation)
      expect(harness.asked).to(include([:run, [1], "mutants (warm)"]))
      expect(isolation.asked).to(include([:run, [2], "mutants (isolated)"]))
    end

    def unjudged
      warm = Kimera::RunReport.new(results: [verdict(1, :harness_error), verdict(2, :killed)])
      isolation = FakeIsolation.new(rejudged: [verdict(1, :killed)])
      [FakeHarness.new(warm, coverage: { 1 => ["t1"] }, isolation: isolation), isolation, warm.to_a.first]
    end

    it "re-judges in the isolated tier what the warm pass could not judge" do
      harness, isolation, warm = unjudged
      report = pass(registry, settings(hard_timeout: 9.0, jobs: 3), [1, 2], harness: harness)
      expect(report.to_a.map { |r| [r.mutant_id, r.status] }).to(eq([[1, :killed], [2, :killed]]))
      expect(isolation.asked).to(eq([[:rejudge, [warm], "mutants (re-judged)"]]))
      expect(isolation.settings).to(include(hard_timeout: 9.0, jobs: 3, tests: ["t1"], filter: anything))
    end

    it "hands the re-judging tier test quality and the seed" do
      harness, isolation, = unjudged
      pass(registry, settings(test_quality: true, seed: 3), [1, 2], harness: harness)
      expect(isolation.settings).to(include(test_quality: true, seed: 3))
    end

    context "when one of two methods needs a second look" do
      let(:registry) do
        Kimera::RegistryScan.new.source("def m(a, b)\n  a > b\nend\n\ndef n(a, b)\n  a < b\nend\n", file: "x.rb")
      end

      # The warm pass gives each method's mutant +status+; the second method's
      # point is marked to revisit for +reason+. Returns the warm harness, the
      # isolated tier, which kills what it re-judges, and both ids.
      def second_look(coverage, status, reason)
        first, last = per_method
        warm = Kimera::RunReport.new(results: [first, last].map { |id| verdict(id, status) })
        registry.index.fetch(last).revisit!(reason)
        isolation = FakeIsolation.new(rejudged: [verdict(last, :killed)])
        [FakeHarness.new(warm, coverage: coverage, isolation: isolation), isolation, first, last]
      end

      # The first mutant of each of the two methods.
      def per_method = registry.each.map { |mutant, point| [mutant.id, point] }.uniq(&:last).first(2).map(&:first)

      def bootstrap = second_look({ 1 => ["t1"], 2 => ["t1"] }, :survived, Kimera::MutationPoint::BOOT_REASON)

      it "re-judges a warm survivor whose method also ran while the suite loaded", :aggregate_failures do
        harness, isolation, kept, booted = bootstrap
        report = pass(registry, settings, [kept, booted], harness: harness)
        expect(report.to_a.map { |r| [r.mutant_id, r.status] }).to(eq([[kept, :survived], [booted, :killed]]))
        rejudged = have_fields(mutant_id: booted, status: :survived, detail: Kimera::MutationPoint::BOOT_REASON)
        expect(isolation.asked).to(match([[:rejudge, [rejudged], "mutants (re-judged)"]]))
      end

      def ordered = second_look({ 1 => ["t1"] }, :no_coverage, Kimera::MutationPoint::ORDER_REASON)

      it "judges in the isolated tier a mutant only the suite run in order reaches", :aggregate_failures do
        harness, isolation, plain, reached = ordered
        report = pass(registry, settings, [plain, reached], harness: harness)
        expect(report.to_a.map { |r| [r.mutant_id, r.status] }).to(eq([[plain, :no_coverage], [reached, :killed]]))
        rejudged = have_fields(mutant_id: reached, detail: Kimera::MutationPoint::ORDER_REASON)
        expect(isolation.asked).to(match([[:rejudge, [rejudged], "mutants (re-judged)"]]))
      end

      it "says why such a mutant has no covering test under --no-rejudge", :aggregate_failures do
        harness, isolation, plain, reached = ordered
        report = pass(registry, settings(rejudge: false), [plain, reached], harness: harness)
        expect(report.to_a.map { |r| [r.mutant_id, r.status, r.detail] })
          .to(eq([[plain, :no_coverage, nil], [reached, :no_coverage, Kimera::MutationPoint::ORDER_REASON]]))
        expect(isolation.asked).to(be_empty)
      end
    end

    it "leaves the warm verdicts alone under --no-rejudge" do
      harness, isolation, = unjudged
      report = pass(registry, settings(rejudge: false), [1, 2], harness: harness)
      expect(report.to_a.map(&:status)).to(eq(%i[harness_error killed]))
      expect(isolation.asked).to(be_empty)
    end

    # Validations and callbacks run once at load: only a fresh process can
    # judge them. An incremental run judges them by default.
    def deferred
      warm = Kimera::RunReport.new(results: [verdict(1, :isolated_only), verdict(2, :killed)])
      isolation = FakeIsolation.new(result(1, :survived))
      [FakeHarness.new(warm, coverage: { 1 => ["t1"] }, isolation: isolation), isolation]
    end

    it "judges isolated-only mutants in the isolated tier on an incremental run", :aggregate_failures do
      harness, isolation = deferred
      report = pass(registry, settings(since: "origin/main"), [1, 2], harness: harness)
      expect(report.to_a.map { |r| [r.mutant_id, r.status] }).to(eq([[1, :survived], [2, :killed]]))
      expect(isolation.asked).to(include([:run, [1], "mutants (isolated)"]))
    end

    it "leaves isolated-only mutants reported on a full run, or when told not to judge them", :aggregate_failures do
      harness, isolation = deferred
      expect(pass(registry, settings, [1, 2], harness: harness).to_a.map(&:status)).to(eq(%i[isolated_only killed]))
      off = settings(since: "origin/main", judge_isolated_only: false)
      expect(pass(registry, off, [1, 2], harness: harness).to_a.map(&:status)).to(eq(%i[isolated_only killed]))
      expect(isolation.asked).to(be_empty)
    end

    it "judges isolated-only mutants on a full run when told to" do
      harness, = deferred
      statuses = pass(registry, settings(judge_isolated_only: true), [1, 2], harness: harness).to_a.map(&:status)
      expect(statuses).to(eq(%i[survived killed]))
    end

    it "isolates only mutants covered by a pool-unsafe spec and merges the reports" do
      harness, isolation = partition
      parsed = settings(isolate_when_covered_by: ["end_to_end_spec"])
      report = pass(registry, parsed, [1, 2], harness: harness, suite: both)
      expect(report.to_a.map(&:mutant_id)).to(contain_exactly(1, 2))
      distribute(harness, isolation)
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
      FileUtils.mkdir_p("spec")
      File.write("spec/calc_spec.rb", "")
      manifest = File.join(dir, "reg.json")
      Kimera::RegistryScan.new.source(File.read("calc.rb"), file: "calc.rb").write(manifest)
      manifest
    end

    def red = described_class.new(bench: FakeBench.new(harness: FailingHarness.new(failure)))

    it "warns and returns 1 when the harness reports the baseline is not green" do
      _out, error, status = transcript { red.run(["calc.rb", "--registry", baseline]) }
      expect(status).to(eq(1))
      expect(error).to(include("kimera: baseline suite is not green"))
    end
  end

  # A typo'd path or glob must fail, not score perfect over nothing.
  describe "empty scope guards" do
    # A --since run finds no line changed.
    subject(:cli) { described_class.new(bench: FakeBench.new) }

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
        [ended(cli.run(argv), $stdout, error), error.string]
      ensure
        $stderr = errors
        $stdout = output
      end
    end

    # A silent no-op exclude widens a CI gate's scope.
    # What loading a.rb as the sources and as the tests, excluding a pattern that matches nothing, warns.
    def unexcluded
      File.write(File.join(dir, "a.rb"), "class A; end\n")
      errors = StringIO.new
      sources = Kimera::CLI::Run::Sources.new(errors: errors)
      sources.load(Kimera::CLI::Run::Settings.new(paths: ["a.rb"], exclude: ["typo/**/*.rb"], source_root: "."))
      sources.tests(["a.rb"], ["typo/**/*.rb"])
      errors.string
    end

    it "warns about exclude patterns that matched nothing" do
      warned = %w[source test].map { |kind| "exclude pattern matched no #{kind} files: typo/**/*.rb" }
      expect(unexcluded).to(eq(warned.map { |warning| "kimera: warning: #{warning}\n" }.join))
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

    it "drops test files matching --exclude-test" do
      fixtures
      harness = FakeHarness.new
      run = described_class.new(io: StringIO.new, bench: FakeBench.new(harness: harness))
      run.run(["calc.rb", "--tests", "spec/**/*_spec.rb", "--exclude-test", "spec/flaky_spec.rb"])
      expect(harness.asked.first[1]).to(eq(["spec/good_spec.rb"]))
    end

    it "stamps no session when the run keeps none" do
      registry = Kimera::RegistryScan.new.source("def m(a, b)\n  a > b\nend\n", file: "calc.rb")
      cycle = Kimera::CLI::Run::Cycle.new({ since: "main", source_root: "." }, registry, digest: nil)
      expect(cycle.__send__(:stamp)).to(be_nil)
    end

    it "still passes quietly when an incremental diff selects zero mutants" do
      File.write("calc.rb", "def m(a, b)\n  a > b\nend\n")
      status, = capture(["calc.rb", "--since", "main"])
      expect(status).to(eq(0))
    end
  end

  describe "#announce_scope" do
    let(:registry) do
      Kimera::RegistryScan.new.source("def m(a, b)\n  a > b\nend\n", file: "x.rb")
    end

    def announced(change, selected, ignored)
      io = StringIO.new
      original = $stdout
      $stdout = io
      Kimera::CLI::Run::Digest.new(emission: nil).announce(change, selected, ignored, files: registry.files.size)
      io.string
    ensure
      $stdout = original
    end

    it "announces incremental scope and ignored counts" do
      out = announced(Kimera::Incremental::Selection.new({}, "main"), [1, 2], [3])
      expect(out.lines).to(
        eq(
          [
            "Incremental: 2 mutants on lines changed since main (1 changed files).\n",
            "Ignoring 1 mutant(s) marked equivalent.\n"
          ]
        )
      )
    end

    it "stays silent when not incremental and nothing is ignored" do
      expect(announced(Kimera::CLI::Run::NullSelection.new, [1, 2], [])).to(eq(""))
    end
  end
end
