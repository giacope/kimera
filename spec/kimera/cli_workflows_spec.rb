# frozen_string_literal: true

require "fileutils"
require "json"
require "kimera/cli"
require "kimera/cli/run"
require "kimera/cli/workflows"
require "kimera/cli/mutant"
require "kimera/cli/baseline"
require "stringio"
require "tmpdir"

RSpec.describe(Kimera::CLI, :aggregate_failures) do
  let(:dir) { Dir.mktmpdir }
  let(:out) { StringIO.new }
  let(:error) { StringIO.new }

  after { FileUtils.remove_entry(dir) }

  def captured
    [StringIO.new, StringIO.new]
  end

  def project(files)
    files.each do |path, body|
      FileUtils.mkdir_p(File.dirname(File.join(dir, path)))
      File.write(File.join(dir, path), body)
    end
  end

  def configure(*argv) = Kimera::CLI::Init.new(io: out, errors: error, root: dir).run(argv)

  def doctor(*argv) = Kimera::CLI::Doctor.new(io: out, errors: error, root: dir).run(argv)

  def configured = YAML.safe_load_file(File.join(dir, ".kimera.yml"))

  def survivor
    { "mutant_id" => 7, "status" => "survived", "file" => "app/a.rb", "line" => 3 }
      .merge("label" => "> => >=", "original" => "x > y", "mutated" => "x >= y")
  end

  def written(dir, document)
    report = File.join(dir, "report.json")
    File.write(report, JSON.generate(document))
    report
  end

  it "initializes a detected RSpec project" do
    project("app/thing.rb" => "class Thing; end\n", "spec/.keep" => "")
    expect(configure).to(eq(0))
    expect(configured).to(include("framework" => "rspec", "paths" => ["app/**/*.rb"], "tests" => ["spec/**/*_spec.rb"]))
    expect(out.string).to(include("Created .kimera.yml", "Next: kimera doctor"))
  end

  it "never overwrites an existing config" do
    project("app/thing.rb" => "class Thing; end\n", ".kimera.yml" => "jobs: 1\n")
    expect(configure).to(eq(1))
    expect(error.string).to(include("already exists"))
  end

  it "leaves the project's agent files alone" do
    project("AGENTS.md" => "# Agents\n")
    configure
    expect(Dir.children(dir).sort).to(eq(%w[.kimera.yml AGENTS.md]))
    expect(File.read(File.join(dir, "AGENTS.md"))).to(eq("# Agents\n"))
  end

  describe "the config init writes" do
    let(:text) do
      project("lib/thing.rb" => "")
      configure
      File.read(File.join(dir, ".kimera.yml"))
    end

    it "names its schema and comments each key" do
      expect(text).to(start_with("# yaml-language-server: $schema=#{Kimera::CLI::ConfigTemplate::SCHEMA}\n"))
      expect(text).to(include("\n# Test framework: rspec or minitest.\nframework: rspec\n\n# Source files to mutate"))
      expect(text).to(include("\n# baseline: .kimera-baseline.yml\n", "# kimera:disable[-next-line]"))
    end

    it "keeps every line within 120 columns and loads back to what it detected" do
      expect(text.lines.map(&:chomp)).to(all(satisfy { |line| line.size <= 120 }))
      keys = %w[framework paths tests operators jobs max_survivors max_errors count_no_coverage]
      expect(YAML.safe_load(text).keys).to(eq(keys))
    end
  end

  it "prints the bundled agent skill" do
    expect(described_class.new(io: out, errors: error).run(["skill"])).to(eq(0))
    skill = File.read(File.expand_path("../../skills/kimera/SKILL.md", __dir__), encoding: Encoding::UTF_8)
    expect(out.string).to(eq(skill))
    expect(out.string).to(start_with("---\nname: kimera\n"))
  end

  it "rejects arguments to skill" do
    expect(Kimera::CLI::Skill.new(io: out, errors: error).run(["extra"])).to(eq(1))
    expect(error.string).to(eq("kimera: usage: kimera skill\n"))
  end

  it "detects Minitest from the helper even when its tests live under spec/" do
    project("lib/thing.rb" => "class Thing; end\n", "spec/spec_helper.rb" => "require 'minitest/autorun'\n")
    project("spec/thing_spec.rb" => "describe(Thing) {}\n")
    configure
    expect(configured).to(include("framework" => "minitest", "tests" => ["spec/**/*_spec.rb"]))
  end

  it "prefers an RSpec mention in the helper and falls back to layout when the helper names neither" do
    project("spec/spec_helper.rb" => "RSpec.configure { |config| config.mock_with(:minitest) }\n")
    configure("--dry-run")
    project("spec/spec_helper.rb" => "# shared setup\n")
    configure("--dry-run")
    expect(out.string.scan(/^framework: \w+/)).to(eq(["framework: rspec", "framework: rspec"]))
  end

  # Neither autorun nor a test class: only the gem's name says Minitest.
  it "detects Minitest from a helper that only requires a Minitest library" do
    project("spec/spec_helper.rb" => "require \"minitest/pride\"\n")
    configure
    expect(configured).to(include("framework" => "minitest"))
  end

  it "configures the default source globs when neither app nor lib holds Ruby" do
    project("spec/thing_spec.rb" => "")
    configure
    expect(configured).to(include("paths" => Kimera::FileSet::DEFAULT_GLOBS))
  end

  it "detects RSpec from .rspec even without a spec directory" do
    project("test/.keep" => "", ".rspec" => "--require spec_helper\n")
    configure("--dry-run")
    expect(YAML.safe_load(out.string)).to(include("framework" => "rspec"))
  end

  it "fails doctor when the configured framework is not in the bundle" do
    project(".kimera.yml" => "framework: minitest\n")
    allow(Gem).to(receive(:find_files).and_call_original)
    allow(Gem).to(receive(:find_files).with("minitest").and_return([]))
    expect(doctor).to(eq(1))
    expect(out.string).to(include("✗ Framework: minitest is not in this bundle"))
  end

  it "fails doctor on an unknown framework" do
    project(".kimera.yml" => "framework: jasmine\n")
    doctor
    expect(out.string).to(include("✗ Framework: unknown jasmine"))
  end

  it "reports actionable doctor failures and successes" do
    project("app/thing.rb" => "class Thing; end\n", "spec/thing_spec.rb" => "RSpec.describe(\"thing\") { it { } }\n")
    project(".kimera.yml" => "paths: [app/**/*.rb]\ntests: [spec/**/*_spec.rb]\n")
    expect(doctor).to(eq(0))
    expect(out.string).to(include("✓ Source scope: 1 Ruby files", "✓ Test discovery: 1 files"))
    expect(error.string).to(eq(""))
  end

  def test_doctor_floor(helper)
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "spec"))
      File.write(File.join(dir, "spec", "spec_helper.rb"), helper)
      out, error = captured
      [Kimera::CLI::Doctor.new(io: out, errors: error, root: dir).run([]), out.string]
    end
  end

  it "warns, without failing, about a coverage floor that partial isolated runs would trip", :aggregate_failures do
    _status, output = test_doctor_floor("SimpleCov.start { minimum_coverage 100 }\n")
    expect(output).to(include("! Coverage floor: minimum_coverage in spec/spec_helper.rb"))
    expect(output).to(include('skip it when ENV["KIMERA"] is set'))
    expect(output).not_to(include("✗ Coverage"))
  end

  it "stays quiet about a coverage floor already gated on KIMERA", :aggregate_failures do
    _status, output = test_doctor_floor(%(SimpleCov.start { minimum_coverage 100 unless ENV["KIMERA"] }\n))
    expect(output).not_to(include("Coverage floor"))
    _status, bare = test_doctor_floor("# no simplecov here\n")
    expect(bare).not_to(include("Coverage floor"))
  end

  # giacope/kimera#19: pundit's floor applies only when COVERAGE is set, and
  # Kimera's runs never set it.
  it "stays quiet about a coverage floor gated on any other env var" do
    _status, output = test_doctor_floor(<<~RUBY)
      if ENV["COVERAGE"]
        require "simplecov"
        SimpleCov.start { add_filter "/spec/" }
        SimpleCov.minimum_coverage_by_file line: 100, branch: 100
      end
    RUBY
    expect(output).not_to(include("Coverage floor"))
  end

  it "reads a minitest helper's floor the same way", :aggregate_failures do
    project("test/test_helper.rb" => %(SimpleCov.minimum_coverage 90 if ENV["COVERAGE"]\nrequire "minitest/autorun"\n))
    expect(test_doctor_in(dir).last).not_to(include("Coverage floor"))
    project("test/test_helper.rb" => %(SimpleCov.minimum_coverage 90\nrequire "minitest/autorun"\n))
    expect(test_doctor_in(dir).last).to(include("! Coverage floor: minimum_coverage in test/test_helper.rb can fail"))
  end

  def test_initialized(files)
    Dir.mktmpdir do |dir|
      files.each do |path, body|
        FileUtils.mkdir_p(File.dirname(File.join(dir, path)))
        File.write(File.join(dir, path), body)
      end
      out, error = captured
      Kimera::CLI::Init.new(io: out, errors: error, root: dir).run(["--dry-run"])
      YAML.safe_load(out.string)
    end
  end

  # `rails test` leaves out test/system; loaded with the rest, once-campfire's
  # Selenium tests need Chrome and also broke unrelated tests.
  describe "a Rails app's system tests" do
    let(:rails) { { "config/application.rb" => "", "test/test_helper.rb" => "require 'minitest'\n" } }

    it "are left out, as rails test does", :aggregate_failures do
      with = test_initialized(rails.merge("test/system/chat_test.rb" => "", "test/models/a_test.rb" => ""))
      expect(with).to(include("tests" => ["test/**/*_test.rb"], "exclude_tests" => ["test/system/**/*_test.rb"]))
      rspec = rails.merge("spec/system/x_spec.rb" => "", ".rspec" => "")
      expect(test_initialized(rspec)).to(include("exclude_tests" => ["spec/system/**/*_spec.rb"]))
    end

    it "leave nothing to exclude when there are none, or when the project is not Rails", :aggregate_failures do
      expect(test_initialized(rails.merge("test/models/a_test.rb" => ""))).not_to(have_key("exclude_tests"))
      plain = test_initialized("test/test_helper.rb" => "require 'minitest'\n", "test/system/x_test.rb" => "")
      expect(plain).not_to(have_key("exclude_tests"))
    end
  end

  # R6B4-M9: hashie's .rspec leaves out spec/integration (each runs under its
  # own Gemfile); init took every spec, and kimera's baseline could not load them.
  describe "the specs a project's .rspec leaves out or picks" do
    def dotted(options) = { ".rspec" => "--require spec_helper\n#{options}\n", "spec/a_spec.rb" => "" }

    it "are left out, or picked, as rspec does", :aggregate_failures do
      expect(test_initialized(dotted("--exclude-pattern 'spec/integration/**/*_spec.rb'")))
        .to(include("tests" => ["spec/**/*_spec.rb"], "exclude_tests" => ["spec/integration/**/*_spec.rb"]))
      expect(test_initialized(dotted("--pattern=spec/unit/**/*_spec.rb")))
        .to(include("tests" => ["spec/unit/**/*_spec.rb"]))
    end

    it "join a Rails app's browser specs" do
      rails = { "config/application.rb" => "", "spec/system/x_spec.rb" => "" }
      app = dotted("--exclude-pattern **/slow/*_spec.rb").merge(rails)
      expect(test_initialized(app)).to(include("exclude_tests" => %w[spec/system/**/*_spec.rb spec/**/slow/*_spec.rb]))
    end
  end

  # K3-1: RSpec Rails apps keep their browser specs in spec/system and spec/features.
  describe "an RSpec Rails app's browser specs" do
    let(:app) { { "config/application.rb" => "", ".rspec" => "", "spec/models/a_spec.rb" => "" } }

    it "are left out, system and feature specs both", :aggregate_failures do
      both = test_initialized(app.merge("spec/system/x_spec.rb" => "", "spec/features/y_spec.rb" => ""))
      expect(both).to(include("exclude_tests" => %w[spec/system/**/*_spec.rb spec/features/**/*_spec.rb]))
      features = test_initialized(app.merge("spec/features/y_spec.rb" => ""))
      expect(features["exclude_tests"]).to(eq(["spec/features/**/*_spec.rb"]))
    end

    it "leave nothing to exclude when there are none" do
      expect(test_initialized(app)).not_to(have_key("exclude_tests"))
    end
  end

  # F4: an engine is any lib file that subclasses Rails::Engine, not only engine.rb.
  it "knows an engine declared outside engine.rb, with its dummy app" do
    engine = {
      "lib/blog/railtie_engine.rb" => "module Blog\n  class Core < ::Rails::Engine\n  end\nend\n",
      "spec/dummy/config/application.rb" => "", ".rspec" => "", "spec/models/a_spec.rb" => ""
    }
    expect(test_initialized(engine)["operators"]).to(include("rails"))
    expect(test_initialized(engine.except("spec/dummy/config/application.rb"))["operators"]).not_to(include("rails"))
  end

  # R3K4: jekyll's helper requires minitest/autorun and rspec/mocks.
  it "calls a suite whose helper runs Minitest minitest, whatever else it loads", :aggregate_failures do
    helper = "require \"minitest/autorun\"\nrequire \"rspec/mocks\"\n"
    expect(test_initialized("test/helper.rb" => helper, "test/test_calc.rb" => "")).to(
      include("framework" => "minitest", "tests" => ["test/**/test_*.rb"])
    )
    tests = { "test/calc_test.rb" => "class CalcTest < Minitest::Test\nend\n", "spec_helper.rb" => "RSpec" }
    expect(test_initialized(tests)["framework"]).to(eq("minitest"))
    expect(test_initialized(tests.merge("spec/a_spec.rb" => ""))["framework"]).not_to(eq("minitest"))
  end

  it "reads Minitest tests under test/ before a helper that names RSpec", :aggregate_failures do
    helper = { "test/helper.rb" => "require \"rspec/mocks\"\n" }
    minitest = helper.merge("test/calc_test.rb" => "class CalcTest < Minitest::Test\nend\n")
    expect(test_initialized(minitest)["framework"]).to(eq("minitest"))
    expect(test_initialized(helper.merge("test/calc_test.rb" => "class CalcTest\nend\n"))["framework"]).to(eq("rspec"))
  end

  it "reads a spec helper that runs Minitest as Minitest, whatever else it loads" do
    helper = {
      "spec/spec_helper.rb" => "require \"minitest/autorun\"\nrequire \"rspec/mocks\"\n",
      "spec/a_spec.rb" => ""
    }
    expect(test_initialized(helper)["framework"]).to(eq("minitest"))
  end

  it "writes at most four workers" do
    allow(Etc).to(receive(:nprocessors).and_return(16))
    expect(test_initialized("spec/a_spec.rb" => "")["jobs"]).to(eq(4))
    allow(Etc).to(receive(:nprocessors).and_return(2))
    expect(test_initialized("spec/a_spec.rb" => "")["jobs"]).to(eq(2))
  end

  # Sequel and graphql-ruby keep Minitest specs under spec/ with no helper
  # that names a framework; the lockfile says which one is installed.
  describe "the framework a lockfile installs" do
    spec = { "spec/core/a_spec.rb" => "describe('x') { }\n" }
    minitest = spec.merge("Gemfile.lock" => "GEM\n  specs:\n    minitest (5.25.1)\n")
    both = "    minitest (5.25.1)\n    rspec-core (3.13.2)\n"
    {
      "minitest from Gemfile.lock" => [minitest, { "framework" => "minitest", "tests" => ["spec/**/*_spec.rb"] }],
      "minitest from gems.locked" => [spec.merge("gems.locked" => "GEM\n  specs:\n    minitest (5.25.1)\n"), {}],
      "rspec over a test/ layout" => [
        { "test/a_test.rb" => "", "Gemfile.lock" => "GEM\n  specs:\n    rspec-core (3.13.2)\n" },
        { "framework" => "rspec" }
      ],
      "the layout's guess when both are installed, under spec/" => [
        minitest.merge("Gemfile.lock" => both), { "framework" => "rspec" }
      ],
      "the layout's guess when both are installed, under test/" => [
        { "test/a_test.rb" => "", "Gemfile.lock" => both }, { "framework" => "minitest" }
      ],
      "no framework from gems that only share a prefix" => [
        spec.merge("Gemfile.lock" => "    minitest-hooks (1.5.2)\n    rspec-core-ext (1.0)\n"),
        { "framework" => "rspec" }
      ]
    }.each do |name, (files, expected)|
      it "picks #{name}" do
        expect(test_initialized(files)).to(include({ "framework" => "minitest" }.merge(expected)))
      end
    end
  end

  it "lets a .rspec file or a helper that names a framework win over the lockfile", :aggregate_failures do
    minitest = { "Gemfile.lock" => "    minitest (5.25.1)\n", "spec/a_spec.rb" => "" }
    expect(test_initialized(minitest.merge(".rspec" => ""))).to(include("framework" => "rspec"))
    helper = { "test/test_helper.rb" => "require 'rspec'\n", "Gemfile.lock" => "    minitest (5.25.1)\n" }
    expect(test_initialized(helper)).to(include("framework" => "rspec"))
  end

  # Validations, callbacks and dependent: options are a Rails app's riskiest
  # declarations; the rails operators mutate them.
  it "turns on the rails operators in a Rails app, and only there", :aggregate_failures do
    rails = test_initialized("config/application.rb" => "", "spec/a_spec.rb" => "")
    expect(rails["operators"]).to(eq([*Kimera::Operators::INIT_KEYS, "rails"]))
    expect(test_initialized("spec/a_spec.rb" => "")["operators"]).not_to(include("rails"))
  end

  # R5 (CodeTriage): the core never mutates a `when` branch or a `<<` statement.
  it "writes the core, `when` branches and `<<` statements into a new project's operators" do
    expected = %w[
      comparison boolean_connective boolean_literal statement_deletion negation conditional when_clause append_deletion
    ]
    expect(test_initialized("spec/a_spec.rb" => "")["operators"]).to(eq(expected))
  end

  # camaleon-cms: an engine with a dummy app has no config/application.rb at
  # its root, and is still Rails (E3).
  describe "an engine with a dummy app" do
    let(:engine) { { "lib/cms/engine.rb" => "module Cms\n  class Engine < ::Rails::Engine\n  end\nend\n" } }

    it "turns on the rails operators", :aggregate_failures do
      dummy = engine.merge("spec/dummy/config/application.rb" => "", "spec/a_spec.rb" => "")
      expect(test_initialized(dummy)["operators"]).to(eq([*Kimera::Operators::INIT_KEYS, "rails"]))
      isolated = { "lib/cms/engine.rb" => "module Cms\n  class Engine\n    isolate_namespace Cms\n  end\nend\n" }
      minitest = isolated.merge("test/dummy/config/application.rb" => "", "test/test_helper.rb" => "require 'minitest'")
      expect(test_initialized(minitest)["operators"]).to(include("rails"))
    end

    it "needs both the engine and the dummy app", :aggregate_failures do
      expect(test_initialized(engine.merge("spec/a_spec.rb" => ""))["operators"]).not_to(include("rails"))
      other = { "lib/cms/engine.rb" => "class Engine; end\n", "spec/dummy/config/application.rb" => "" }
      expect(test_initialized(other)["operators"]).not_to(include("rails"))
    end
  end

  # count_no_coverage, on by default, is what gates uncovered mutants; init
  # writes it with its description instead of the redundant gate flag.
  it "writes count_no_coverage, not fail_on_no_coverage", :aggregate_failures do
    configure("--dry-run")
    expect(out.string).to(include("# Score a mutant with no covering test as not killed", "count_no_coverage: true"))
    expect(out.string).not_to(include("fail_on_no_coverage"))
  end

  # rack names its tests test/spec_*.rb; rake-style gems use test/test_*.rb.
  it "finds minitest files named test_*.rb or spec_*.rb", :aggregate_failures do
    helper = { "test/helper.rb" => "require 'minitest/autorun'\n" }
    expect(test_initialized(helper.merge("test/spec_utils.rb" => ""))).to(include("tests" => ["test/**/spec_*.rb"]))
    expect(test_initialized(helper.merge("test/test_task.rb" => ""))).to(include("tests" => ["test/**/test_*.rb"]))
  end

  # R4-KL3: zeitwerk's support class test/support/loader_test.rb and its tests test/**/test_*.rb.
  def zeitwerk_like
    { "test/helper.rb" => "require 'minitest/autorun'\n", "test/support/loader_test.rb" => "", "test/b_test.rb" => "" }
  end

  it "picks the minitest glob whose files define the most tests", :aggregate_failures do
    tests = zeitwerk_like.merge("test/lib/test_calc.rb" => "class CalcTest < LoaderTest\n  def test_one; end\nend\n")
    expect(test_initialized(tests)).to(include("tests" => ["test/**/test_*.rb"]))
    expect(test_initialized(zeitwerk_like)).to(include("tests" => ["test/**/*_test.rb"]))
    expect(test_initialized(zeitwerk_like.slice("test/helper.rb"))).to(include("tests" => ["test/**/*_test.rb"]))
  end

  def test_doctor_in(dir, *argv)
    out, error = captured
    [Kimera::CLI::Doctor.new(io: out, errors: error, root: dir).run(argv), out.string]
  end

  def green_suite(seen = [])
    allow(Kimera::Execution::SUITE).to(receive(:call)) do |_env, *command, **|
      seen << [command, out.string]
      ["", instance_double(Process::Status, success?: true)]
    end
    seen
  end

  describe "a doctor run where no test file matches" do
    before do
      project(".kimera.yml" => "tests: [test/**/*_test.rb]\n")
      allow(Kimera::Execution::SUITE).to(receive(:call))
    end

    it "fails discovery and skips loading", :aggregate_failures do
      expect(doctor("--check-baseline")).to(eq(1))
      expect(out.string).to(include("✗ Test discovery", "! Test loading: no test files to load"))
    end

    it "never runs the baseline", :aggregate_failures do
      doctor("--check-baseline")
      expect(out.string).not_to(include("Baseline"))
      expect(Kimera::Execution::SUITE).not_to(have_received(:call))
    end
  end

  it "fails discovery when the test files define no test" do
    project("test/support/loader_test.rb" => "class LoaderTest < Minitest::Test\nend\n")
    project(".kimera.yml" => "framework: minitest\ntests: [test/**/*_test.rb]\n")
    green_suite && expect(test_doctor_in(dir)).to(
      match([1, include("✗ Test discovery: 1 files match tests:, but none defines a test")])
    )
  end

  it "leaves the configured exclude_tests out of discovery", :aggregate_failures do
    project("test/a_test.rb" => "def test_a; end\n", "test/system/b_test.rb" => "def test_b; end\n")
    project(".kimera.yml" => "tests: [test/**/*_test.rb]\nexclude_tests: [test/system/**/*_test.rb]\n")
    green_suite && expect(test_doctor_in(dir).last).to(include("✓ Test discovery: 1 files"))
    green = "✓ Baseline: configured test suite is green\n"
    expect(test_doctor_in(dir, "--check-baseline").last.lines.last).to(eq(green))
  end

  # Output piped to a file or CI log must show doctor working before the
  # suite run, which can take minutes.
  describe "a doctor run whose output is piped" do
    let(:out) { Class.new(StringIO) { define_method(:flushed) { @_flushed ||= [] } }.new }

    it "prints each check before the suite runs", :aggregate_failures do
      project("spec/a_spec.rb" => "it { }\n")
      seen = green_suite
      doctor("--check-baseline")
      expect(seen.first.last).to(include("✓ Test discovery: 1 files", "Git:"))
      expect(seen.last.last).to(include("✓ Test loading"))
    end

    it "flushes after every line" do
      project("spec/a_spec.rb" => "")
      allow(out).to(receive(:flush)) { out.flushed << out.string.lines.size }
      green_suite && doctor("--check-baseline")
      expect(out.flushed).to(eq((1..out.string.lines.size).to_a))
    end
  end

  # R6B4-M8: strong_migrations' configuration leaves out a test that fails
  # here; `kimera run` left it out, doctor ran it and called the suite red.
  it "runs the baseline without the tests exclude_test_names leaves out, as run does" do
    project("spec/a_spec.rb" => "", ".kimera.yml" => "exclude_test_names: [\"needs a network\"]\njobs: 1\n")
    seen = green_suite.tap { doctor("--check-baseline") }
    expect(seen.map { |command, _| command.join(" ") }).to(all(include("filter_run_excluding", "needs a network")))
  end

  describe "the configured load path" do
    let!(:seen) do
      config = "framework: minitest\ntests: [spec/**/*_spec.rb]\nload_path: [support, spec/helpers]\n"
      project("spec/a_spec.rb" => "", ".kimera.yml" => config)
      green_suite.tap { doctor }
    end

    after { ENV.delete("KIMERA_LOAD_PATH") }

    it "is on the suite's command line, as kimera run puts it" do
      expect(seen.first.first).to(start_with(*%w[bundle exec ruby -I support -I spec/helpers -I spec]))
    end

    it "reaches the suite through KIMERA_LOAD_PATH" do
      expect(ENV.fetch("KIMERA_LOAD_PATH")).to(eq("support#{File::PATH_SEPARATOR}spec/helpers"))
    end
  end

  def test_doctor_jobs(config, *argv, serial: true)
    project("spec/a_spec.rb" => "", ".kimera.yml" => config)
    allow(Kimera::Execution::SUITE).to(receive(:call)) do |_env, *command, **|
      ["", instance_double(Process::Status, success?: serial || command.include?("--dry-run"))]
    end
    test_doctor_in(dir, "--check-baseline", *argv).last
  end

  # A suite that is green in one process can still be red on the configured
  # workers; doctor runs it split across that many processes too.
  describe "the parallel baseline" do
    let(:parallel) do
      "✓ Parallel baseline: green split across 3 processes too (jobs: 3; #{Kimera::CLI::TestCommand::SAMPLE})\n"
    end

    it "runs split across the configured jobs, or those --jobs gives", :aggregate_failures do
      expect(test_doctor_jobs("jobs: 3\n").lines.last).to(eq(parallel))
      expect(Kimera::Execution::SUITE).to(have_received(:call).exactly(5).times)
      expect(test_doctor_jobs("{}\n", "--jobs", "3").lines.last).to(eq(parallel))
    end

    [["jobs: 3\n", "--jobs", "1"], ["jobs: 1\n"], ["{}\n"], ["jobs: many\n"], ["jobs:\n"]].each do |config, *argv|
      it "does not run for #{config.inspect} #{argv.join(" ")}".rstrip do
        expect(test_doctor_jobs(config, *argv)).not_to(include("Parallel"))
      end
    end

    it "does not run when the suite is red serially", :aggregate_failures do
      red = test_doctor_jobs("jobs: 3\n", serial: false)
      expect(red).to(include("✗ Baseline"))
      expect(red).not_to(include("Parallel"))
    end
  end

  # thor keeps its floor in spec/helper.rb.
  it "finds a coverage floor in any spec or test helper" do
    project("spec/support/.keep" => "", "spec/helper.rb" => "SimpleCov.start { minimum_coverage(90) }\n")
    expect(test_doctor_in(dir).last).to(include("! Coverage floor: minimum_coverage in spec/helper.rb"))
  end

  # A .simplecov symlinked to a shared config that isn't checked out.
  it "passes over a helper path that is not a readable file" do
    File.symlink(File.join(dir, "missing.rb"), File.join(dir, ".simplecov"))
    expect(test_doctor_in(dir).last).not_to(include("Coverage floor"))
  end

  # K3-6: outside GitHub, ci silently ran a full run that judged no DSL.
  def ci_given(env, argv = [])
    out, error = captured
    runner = instance_double(Kimera::CLI::Run, run: 0)
    allow(Kimera::CLI::Run).to(receive(:new).and_return(runner))
    Kimera::CLI::CI.new(io: out, errors: error, env: env).run(argv)
    given = nil
    expect(runner).to(have_received(:run) { |arguments| given = arguments })
    [given, error.string]
  end

  it "adds strict CI defaults without replacing explicit user choices" do
    arguments, = ci_given({}, ["--format", "sarif", "--max-survivors", "2"])
    expect(arguments).to(eq(["--format", "sarif", "--max-survivors", "2", "--fail-on-no-coverage"]))
  end

  it "mutates a pull request's changed lines and summarizes the job when GitHub Actions says how" do
    arguments, = ci_given("GITHUB_BASE_REF" => "main", "GITHUB_STEP_SUMMARY" => "/tmp/step.md")
    expect(arguments).to(include("--since", "origin/main", "--summary", "/tmp/step.md"))
  end

  it "leaves an explicit --since and --summary alone" do
    env = { "GITHUB_BASE_REF" => "main", "GITHUB_STEP_SUMMARY" => "/tmp/step.md" }
    arguments, = ci_given(env, ["--since", "HEAD~1", "--summary=s.md"])
    expect(arguments).not_to(include("origin/main", "/tmp/step.md", "--summary"))
  end

  it "leaves an empty environment variable unused" do
    arguments, = ci_given("GITHUB_BASE_REF" => "", "GITHUB_STEP_SUMMARY" => "")
    expect(arguments).not_to(include("--since", "--summary"))
  end

  it "preserves equals-form CI overrides", :aggregate_failures do
    arguments, = ci_given({}, ["--format=sarif", "--max-survivors=2", "--report=out.json"])
    expect(arguments).to(include("--format=sarif", "--max-survivors=2", "--report=out.json"))
    expect(arguments).not_to(include("github"))
  end

  it "takes a pull request's base from KIMERA_BASE, GitLab or Buildkite too", :aggregate_failures do
    expect(ci_given("KIMERA_BASE" => "upstream/dev", "GITHUB_BASE_REF" => "main").first).to(include("upstream/dev"))
    expect(ci_given("CI_MERGE_REQUEST_TARGET_BRANCH_NAME" => "trunk").first).to(include("--since", "origin/trunk"))
    expect(ci_given("BUILDKITE_PULL_REQUEST_BASE_BRANCH" => "main").first).to(include("--since", "origin/main"))
    expect(ci_given("BUILDKITE_PULL_REQUEST_BASE_BRANCH" => "false").first).not_to(include("--since"))
  end

  it "says when it found no base, what it looked for, and what a full run leaves ungated", :aggregate_failures do
    arguments, said = ci_given({})
    expect(arguments).not_to(include("--since"))
    expect(said).to(start_with("kimera ci: no pull request base found (looked for --since, KIMERA_BASE, GITHUB_"))
    expect(said).to(include("unjudged and ungated; pass --judge-isolated-only"))
    expect(ci_given({}, ["--since", "HEAD~2"]).last).to(be_empty)
  end

  it "prints its own usage for --help" do
    expect(Kimera::CLI::CI.new(io: out, errors: error, env: {}).run(["--help"])).to(eq(0))
    expect(out.string).to(start_with("Usage: kimera ci [paths...] [options]\nkimera run with gate defaults"))
    expect(out.string).to(include("--judge-isolated-only"))
  end

  # The report's run section records what the run did, not the raw flag.
  def effective(options)
    Kimera::CLI::Run::Cycle.new(options, nil, digest: nil).__send__(:provenance)
      .slice("judge_isolated_only", "confirm_survivors")
  end

  it "records the effective survivor confirmation and DSL judging", :aggregate_failures do
    expect(effective(since: "HEAD~1")).to(eq("judge_isolated_only" => true, "confirm_survivors" => true))
    expect(effective({})).to(eq("judge_isolated_only" => false, "confirm_survivors" => false))
    expect(effective(since: "HEAD~1", confirm_survivors: false)).to(include("confirm_survivors" => false))
  end

  it "prints shell completion scripts" do
    expect(Kimera::CLI::Completion.new(io: out, errors: error).run(["bash"])).to(eq(0))
    expect(out.string).to(include("complete -F _kimera kimera", "changed", " report "))
    expect(out.string).not_to(match(/\b(dump|survivors)\b/))
  end

  it "suggests a command for a typo" do
    expect(described_class.new(io: out, errors: error).run(["rn"])).to(eq(1))
    expect(error.string).to(include('did you mean "run"?', "Try: kimera help"))
  end

  def baseline(*argv) = Dir.chdir(dir) { Kimera::CLI::Baseline.new(io: out, errors: error).run(argv) }

  it "creates and reviews an explicit, reasoned baseline" do
    report = written(dir, "results" => [survivor])
    expect(baseline("create", report, "--reason", "adoption debt", "--output", "b.yml")).to(eq(0))
    expect(YAML.safe_load_file(File.join(dir, "b.yml")).fetch("ignore").first).to(include("reason" => "adoption debt"))
    expect(baseline("review", "b.yml")).to(eq(0))
    expect(out.string).to(include("1 accepted mutant(s)", "app/a.rb:3 [> => >=] — adoption debt"))
  end

  it "rejects an unknown baseline subcommand, or none" do
    expect([baseline("unknown"), baseline]).to(eq([1, 1]))
    expect(error.string).to(include('kimera: unknown baseline command "unknown"', "Usage: kimera baseline <command>"))
    expect(error.string).to(include("kimera: missing command\n"))
  end

  %w[--help -h help].each do |flag|
    it "prints the baseline commands for #{flag}", :aggregate_failures do
      expect(baseline(flag)).to(eq(0))
      expect(out.string).to(start_with("Usage: kimera baseline <command> [options]\n"))
      commands = ["create [REPORT.json] --reason TEXT [--write]", "review BASELINE.yml", "prune BASELINE.yml"]
      expect(out.string).to(include(*commands))
    end
  end

  describe "create --write" do
    let(:report) { written(dir, "results" => [survivor.merge("line" => 3, "label" => "> => >=")]) }

    it "sets the new baseline in .kimera.yml, replacing a commented line", :aggregate_failures do
      project(".kimera.yml" => "jobs: 2\n# baseline: old.yml\n")
      expect(baseline("create", report, "--reason", "adopting", "--write")).to(eq(0))
      expect(File.read(File.join(dir, ".kimera.yml"))).to(eq("jobs: 2\nbaseline: .kimera-baseline.yml\n"))
      expect(out.string).to(include("Set `baseline: .kimera-baseline.yml` in .kimera.yml."))
    end

    it "sets the baseline it wrote with --output" do
      project(".kimera.yml" => "jobs: 2")
      baseline("create", report, "--reason", "adopting", "--write", "--force", "--output", "b.yml")
      expect(File.read(File.join(dir, ".kimera.yml"))).to(eq("jobs: 2\nbaseline: b.yml\n"))
    end

    it "refuses without a .kimera.yml, and reads the default report", :aggregate_failures do
      project("tmp/kimera/report.json" => JSON.generate("results" => [survivor.merge("line" => 3, "label" => "x")]))
      expect(baseline(*%w[create --reason adopting --write])).to(eq(1))
      expect(error.string).to(include("no .kimera.yml to set the baseline in (run kimera init first)"))
      expect(File.read(File.join(dir, ".kimera-baseline.yml"))).to(include("file: app/a.rb"))
    end
  end

  it "uses report as the friendly survivors alias and mutant as focused detail" do
    report = written(dir, "results" => [survivor])
    cli = described_class.new(io: out, errors: error)
    expect([cli.run(["report", report]), cli.run(["mutant", "7", "--report", report])]).to(eq([0, 0]))
    expect(out.string).to(include("1 survived mutant(s):", "#7  survived  app/a.rb:3\n"))
  end

  describe "a mutant's key" do
    let(:report) { written(dir, "results" => [survivor.merge("key" => "app/a.rb:3:0123abcd")]) }
    let(:cli) { described_class.new(io: out, errors: error) }

    it "finds the mutant and shows in place of file:line" do
      expect(cli.run(["mutant", "app/a.rb:3:0123abcd", "--report", report])).to(eq(0))
      expect(cli.run(["report", report])).to(eq(0))
      expect(out.string).to(include("#7  survived  app/a.rb:3:0123abcd\n", "  #7  app/a.rb:3:0123abcd  [> => >=]"))
      expect(out.string).to(include("detail: kimera mutant <ID|KEY> --report #{report}"))
    end

    it "says when no mutant has it" do
      expect(cli.run(["mutant", "app/a.rb:3:ffffffff", "--report", report])).to(eq(1))
      expect(error.string).to(include("no mutant #app/a.rb:3:ffffffff in this report"))
    end
  end

  describe "--rerun" do
    let(:runner) { instance_double(Kimera::CLI::Run, run: 2) }

    before { allow(Kimera::CLI::Run).to(receive(:new).and_return(runner)) }

    def rerun(row)
      provenance = { "framework" => "rspec", "source_root" => ".", "tests" => ["spec/**/*_spec.rb"] }
        .merge("operators" => ["comparison"], "coverage" => true, "isolated" => false)
      report = written(dir, "run" => provenance, "results" => [row.merge("key" => "app/a.rb:3:0123abcd")])
      Kimera::CLI::Mutant.new(io: out, errors: error).run(["7", "--report", report, "--rerun"])
    end

    it "re-runs only the requested mutant", :aggregate_failures do
      expect(rerun(survivor.slice("mutant_id", "status", "file"))).to(eq(2))
      expect(runner).to(
        have_received(:run).with(
          ["app/a.rb", "--focus", "app/a.rb:3:0123abcd", "--framework", "rspec", "--source-root", "."]
            .push("--tests", "spec/**/*_spec.rb", "--operators", "comparison", "--no-report")
        )
      )
      expect(out.string).to(eq("Re-running mutant #7: app/a.rb:3:0123abcd\n"))
    end

    it "evaluates an ignored mutant" do
      rerun("mutant_id" => 7, "status" => "ignored", "file" => "app/a.rb")
      expect(runner).to(have_received(:run).with(array_including("--evaluate-ignored")))
    end
  end
end
