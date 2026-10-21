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
  def captured
    [StringIO.new, StringIO.new]
  end

  def survivor
    { "mutant_id" => 7, "status" => "survived", "file" => "app/a.rb", "line" => 3 }
      .merge("label" => "> => >=", "original" => "x > y", "mutated" => "x >= y")
  end

  def written(dir, document)
    report = File.join(dir, "report.json")
    File.write(report, JSON.generate(document))
    report
  end

  it "initializes a detected RSpec project without overwriting existing config" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "app"))
      FileUtils.mkdir_p(File.join(dir, "spec"))
      File.write(File.join(dir, "app", "thing.rb"), "class Thing; end\n")
      out, error = captured
      status = Kimera::CLI::Init.new(io: out, errors: error, root: dir).run([])
      config = YAML.safe_load_file(File.join(dir, ".kimera.yml"))
      expect(status).to(eq(0))
      expect(config).to(include("framework" => "rspec", "paths" => ["app/**/*.rb"], "tests" => ["spec/**/*_spec.rb"]))
      expect(out.string).to(include("Created .kimera.yml", "Next: kimera doctor"))
      expect(Kimera::CLI::Init.new(io: out, errors: error, root: dir).run([])).to(eq(1))
      expect(error.string).to(include("already exists"))
    end
  end

  it "leaves the project's agent files alone" do
    Dir.mktmpdir do |dir|
      agents = File.join(dir, "AGENTS.md")
      File.write(agents, "# Agents\n")
      out, error = captured
      Kimera::CLI::Init.new(io: out, errors: error, root: dir).run([])
      expect(Dir.children(dir).sort).to(eq(%w[.kimera.yml AGENTS.md]))
      expect(File.read(agents)).to(eq("# Agents\n"))
    end
  end

  it "writes a commented config that names its schema and loads back to what it detected", :aggregate_failures do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib"))
      File.write(File.join(dir, "lib", "thing.rb"), "")
      out, error = captured
      Kimera::CLI::Init.new(io: out, errors: error, root: dir).run([])
      text = File.read(File.join(dir, ".kimera.yml"))
      expect(text).to(start_with("# yaml-language-server: $schema=#{Kimera::CLI::ConfigTemplate::SCHEMA}\n"))
      expect(text).to(include("\n# Test framework: rspec or minitest.\nframework: rspec\n\n# Source files to mutate"))
      expect(text).to(include("\n# baseline: .kimera-baseline.yml\n", "# kimera:disable[-next-line]"))
      expect(text.lines.map(&:chomp)).to(all(satisfy { |line| line.size <= 120 }))
      keys = %w[framework paths tests jobs max_survivors max_errors count_no_coverage]
      expect(YAML.safe_load(text).keys).to(eq(keys))
    end
  end

  it "prints the bundled agent skill and rejects arguments" do
    out, error = captured
    expect(described_class.new(io: out, errors: error).run(["skill"])).to(eq(0))
    skill = File.read(File.expand_path("../../skills/kimera/SKILL.md", __dir__), encoding: Encoding::UTF_8)
    expect(out.string).to(eq(skill))
    expect(out.string).to(start_with("---\nname: kimera\n"))
    expect(Kimera::CLI::Skill.new(io: out, errors: error).run(["extra"])).to(eq(1))
    expect(error.string).to(eq("kimera: usage: kimera skill\n"))
  end

  it "detects Minitest from the helper even when its tests live under spec/" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib"))
      FileUtils.mkdir_p(File.join(dir, "spec"))
      File.write(File.join(dir, "lib", "thing.rb"), "class Thing; end\n")
      File.write(File.join(dir, "spec", "spec_helper.rb"), "require 'minitest/autorun'\n")
      File.write(File.join(dir, "spec", "thing_spec.rb"), "describe(Thing) {}\n")
      out, error = captured
      Kimera::CLI::Init.new(io: out, errors: error, root: dir).run([])
      config = YAML.safe_load_file(File.join(dir, ".kimera.yml"))
      expect(config).to(include("framework" => "minitest", "tests" => ["spec/**/*_spec.rb"]))
    end
  end

  it "prefers an RSpec mention in the helper and falls back to layout when the helper names neither" do
    Dir.mktmpdir do |dir|
      helper = File.join(dir, "spec", "spec_helper.rb")
      FileUtils.mkdir_p(File.dirname(helper))
      File.write(helper, "RSpec.configure { |config| config.mock_with(:minitest) }\n")
      out, error = captured
      Kimera::CLI::Init.new(io: out, errors: error, root: dir).run(["--dry-run"])
      File.write(helper, "# shared setup\n")
      Kimera::CLI::Init.new(io: out, errors: error, root: dir).run(["--dry-run"])
      expect(out.string.scan(/^framework: \w+/)).to(eq(["framework: rspec", "framework: rspec"]))
    end
  end

  it "detects RSpec from .rspec even without a spec directory" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "test"))
      File.write(File.join(dir, ".rspec"), "--require spec_helper\n")
      out, error = captured
      Kimera::CLI::Init.new(io: out, errors: error, root: dir).run(["--dry-run"])
      expect(YAML.safe_load(out.string)).to(include("framework" => "rspec"))
    end
  end

  it "fails doctor when the configured framework is not in the bundle" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, ".kimera.yml"), "framework: minitest\n")
      allow(Gem).to(receive(:find_files).and_call_original)
      allow(Gem).to(receive(:find_files).with("minitest").and_return([]))
      out, error = captured
      expect(Kimera::CLI::Doctor.new(io: out, errors: error, root: dir).run([])).to(eq(1))
      expect(out.string).to(include("✗ Framework: minitest is not in this bundle"))
      File.write(File.join(dir, ".kimera.yml"), "framework: jasmine\n")
      Kimera::CLI::Doctor.new(io: out, errors: error, root: dir).run([])
      expect(out.string).to(include("✗ Framework: unknown jasmine"))
    end
  end

  it "reports actionable doctor failures and successes" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "app"))
      FileUtils.mkdir_p(File.join(dir, "spec"))
      File.write(File.join(dir, "app", "thing.rb"), "class Thing; end\n")
      File.write(File.join(dir, "spec", "thing_spec.rb"), "# spec\n")
      File.write(File.join(dir, ".kimera.yml"), "paths: [app/**/*.rb]\ntests: [spec/**/*_spec.rb]\n")
      out, error = captured
      status = Kimera::CLI::Doctor.new(io: out, errors: error, root: dir).run([])
      expect(status).to(eq(0))
      expect(out.string).to(include("✓ Source scope: 1 Ruby files", "✓ Test discovery: 1 files"))
      expect(error.string).to(eq(""))
    end
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
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "test"))
      helper = File.join(dir, "test", "test_helper.rb")
      File.write(helper, %(SimpleCov.minimum_coverage 90 if ENV["COVERAGE"]\nrequire "minitest/autorun"\n))
      expect(test_doctor_in(dir).last).not_to(include("Coverage floor"))
      File.write(helper, %(SimpleCov.minimum_coverage 90\nrequire "minitest/autorun"\n))
      expect(test_doctor_in(dir).last).to(include("! Coverage floor: minimum_coverage in test/test_helper.rb can fail"))
    end
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
  it "leaves a Rails app's system tests out, as rails test does", :aggregate_failures do
    rails = { "config/application.rb" => "", "test/test_helper.rb" => "require 'minitest'\n" }
    with = test_initialized(rails.merge("test/system/chat_test.rb" => "", "test/models/a_test.rb" => ""))
    expect(with).to(include("tests" => ["test/**/*_test.rb"], "exclude_tests" => ["test/system/**/*_test.rb"]))
    expect(test_initialized(rails.merge("test/models/a_test.rb" => ""))).not_to(have_key("exclude_tests"))
    plain = test_initialized("test/test_helper.rb" => "require 'minitest'\n", "test/system/x_test.rb" => "")
    expect(plain).not_to(have_key("exclude_tests"))
    rspec = rails.merge("spec/system/x_spec.rb" => "", ".rspec" => "")
    expect(test_initialized(rspec)).to(include("exclude_tests" => ["spec/system/**/*_spec.rb"]))
  end

  # K3-1: RSpec Rails apps keep their browser specs in spec/system and spec/features.
  it "leaves an RSpec Rails app's system and feature specs out", :aggregate_failures do
    app = { "config/application.rb" => "", ".rspec" => "", "spec/models/a_spec.rb" => "" }
    both = test_initialized(app.merge("spec/system/x_spec.rb" => "", "spec/features/y_spec.rb" => ""))
    expect(both).to(include("exclude_tests" => %w[spec/system/**/*_spec.rb spec/features/**/*_spec.rb]))
    features = test_initialized(app.merge("spec/features/y_spec.rb" => ""))
    expect(features).to(include("exclude_tests" => ["spec/features/**/*_spec.rb"]))
    expect(test_initialized(app)).not_to(have_key("exclude_tests"))
  end

  # F4: an engine is any lib file that subclasses Rails::Engine, not only engine.rb.
  it "knows an engine declared outside engine.rb, with its dummy app" do
    engine = {
      "lib/blog/railtie_engine.rb" => "module Blog\n  class Core < ::Rails::Engine\n  end\nend\n",
      "spec/dummy/config/application.rb" => "", ".rspec" => "", "spec/models/a_spec.rb" => ""
    }
    expect(test_initialized(engine)["operators"]).to(include("rails"))
    expect(test_initialized(engine.except("spec/dummy/config/application.rb"))).not_to(have_key("operators"))
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
  it "picks the framework the lockfile installs when the layout would guess", :aggregate_failures do
    spec = { "spec/core/a_spec.rb" => "describe('x') { }\n" }
    minitest = spec.merge("Gemfile.lock" => "GEM\n  specs:\n    minitest (5.25.1)\n")
    expect(test_initialized(minitest)).to(include("framework" => "minitest", "tests" => ["spec/**/*_spec.rb"]))
    locked = spec.merge("gems.locked" => "GEM\n  specs:\n    minitest (5.25.1)\n")
    expect(test_initialized(locked)).to(include("framework" => "minitest"))
    rspec = { "test/a_test.rb" => "", "Gemfile.lock" => "GEM\n  specs:\n    rspec-core (3.13.2)\n" }
    expect(test_initialized(rspec)).to(include("framework" => "rspec"))
    both = "    minitest (5.25.1)\n    rspec-core (3.13.2)\n"
    expect(test_initialized(minitest.merge("Gemfile.lock" => both))).to(include("framework" => "rspec"))
    expect(test_initialized("test/a_test.rb" => "", "Gemfile.lock" => both)).to(include("framework" => "minitest"))
    named = spec.merge("Gemfile.lock" => "    minitest-hooks (1.5.2)\n    rspec-core-ext (1.0)\n")
    expect(test_initialized(named)).to(include("framework" => "rspec"))
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
    expect(rails["operators"]).to(eq([*Kimera::Operators::DEFAULT_KEYS, "rails"]))
    expect(test_initialized("spec/a_spec.rb" => "")).not_to(have_key("operators"))
  end

  # camaleon-cms: an engine with a dummy app has no config/application.rb at
  # its root, and is still Rails (E3).
  it "turns on the rails operators for an engine with a dummy app", :aggregate_failures do
    engine = { "lib/cms/engine.rb" => "module Cms\n  class Engine < ::Rails::Engine\n  end\nend\n" }
    dummy = engine.merge("spec/dummy/config/application.rb" => "", "spec/a_spec.rb" => "")
    expect(test_initialized(dummy)["operators"]).to(eq([*Kimera::Operators::DEFAULT_KEYS, "rails"]))
    isolated = { "lib/cms/engine.rb" => "module Cms\n  class Engine\n    isolate_namespace Cms\n  end\nend\n" }
    minitest = isolated.merge("test/dummy/config/application.rb" => "", "test/test_helper.rb" => "require 'minitest'\n")
    expect(test_initialized(minitest)["operators"]).to(include("rails"))
    expect(test_initialized(engine.merge("spec/a_spec.rb" => ""))).not_to(have_key("operators"))
    other = { "lib/cms/engine.rb" => "class Engine; end\n", "spec/dummy/config/application.rb" => "" }
    expect(test_initialized(other)).not_to(have_key("operators"))
  end

  # count_no_coverage, on by default, is what gates uncovered mutants; init
  # writes it with its description instead of the redundant gate flag.
  it "writes count_no_coverage, not fail_on_no_coverage", :aggregate_failures do
    Dir.mktmpdir do |dir|
      out, error = captured
      Kimera::CLI::Init.new(io: out, errors: error, root: dir).run(["--dry-run"])
      expect(out.string).to(include("# Score a mutant with no covering test as not killed", "count_no_coverage: true"))
      expect(out.string).not_to(include("fail_on_no_coverage"))
    end
  end

  # rack names its tests test/spec_*.rb; rake-style gems use test/test_*.rb.
  it "finds minitest files named test_*.rb or spec_*.rb", :aggregate_failures do
    helper = { "test/helper.rb" => "require 'minitest/autorun'\n" }
    expect(test_initialized(helper.merge("test/spec_utils.rb" => ""))).to(include("tests" => ["test/**/spec_*.rb"]))
    expect(test_initialized(helper.merge("test/test_task.rb" => ""))).to(include("tests" => ["test/**/test_*.rb"]))
  end

  def test_doctor_in(dir, *argv)
    out, error = captured
    [Kimera::CLI::Doctor.new(io: out, errors: error, root: dir).run(argv), out.string]
  end

  it "skips loading and the baseline when no test file matches", :aggregate_failures do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, ".kimera.yml"), "tests: [test/**/*_test.rb]\n")
      allow(Kimera::Execution::SUITE).to(receive(:call))
      status, output = test_doctor_in(dir, "--check-baseline")
      expect(status).to(eq(1))
      expect(output).to(include("✗ Test discovery", "! Test loading: no test files to load"))
      expect(output).not_to(include("Baseline"))
      expect(Kimera::Execution::SUITE).not_to(have_received(:call))
    end
  end

  it "leaves the configured exclude_tests out of discovery", :aggregate_failures do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "test", "system"))
      File.write(File.join(dir, "test", "a_test.rb"), "")
      File.write(File.join(dir, "test", "system", "b_test.rb"), "")
      config = "tests: [test/**/*_test.rb]\nexclude_tests: [test/system/**/*_test.rb]\n"
      File.write(File.join(dir, ".kimera.yml"), config)
      allow(Kimera::Execution::SUITE).to(
        receive(:call).and_return(
          [
            "",
            instance_double(Process::Status, success?: true)
          ]
        )
      )
      expect(test_doctor_in(dir).last).to(include("✓ Test discovery: 1 files"))
      green = "✓ Baseline: configured test suite is green\n"
      expect(test_doctor_in(dir, "--check-baseline").last.lines.last).to(eq(green))
    end
  end

  # Output piped to a file or CI log must show doctor working before the
  # suite run, which can take minutes.
  it "prints each check, flushed, before the suite runs", :aggregate_failures do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "spec"))
      File.write(File.join(dir, "spec", "a_spec.rb"), "")
      out = Class.new(StringIO) { define_method(:flushed) { @_flushed ||= [] } }.new
      allow(out).to(receive(:flush)) { out.flushed << out.string.lines.size }
      seen = []
      allow(Kimera::Execution::SUITE).to(receive(:call)) do
        seen << out.string
        ["", instance_double(Process::Status, success?: true)]
      end
      Kimera::CLI::Doctor.new(io: out, errors: StringIO.new, root: dir).run(["--check-baseline"])
      expect(seen.first).to(include("✓ Test discovery: 1 files", "Git:"))
      expect(seen.last).to(include("✓ Test loading"))
      expect(out.flushed).to(eq((1..out.string.lines.size).to_a))
    end
  end

  it "runs the suite with the configured load path, as kimera run does" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "spec"))
      File.write(File.join(dir, "spec", "a_spec.rb"), "")
      config = "framework: minitest\ntests: [spec/**/*_spec.rb]\nload_path: [support, spec/helpers]\n"
      File.write(File.join(dir, ".kimera.yml"), config)
      seen = []
      allow(Kimera::Execution::SUITE).to(receive(:call)) do |_env, *command, **|
        seen << command
        ["", instance_double(Process::Status, success?: true)]
      end
      test_doctor_in(dir)
      expect(ENV.fetch("KIMERA_LOAD_PATH")).to(eq("support#{File::PATH_SEPARATOR}spec/helpers"))
      expect(seen.first).to(start_with("bundle", "exec", "ruby", "-I", "support", "-I", "spec/helpers", "-I", "spec"))
    ensure
      ENV.delete("KIMERA_LOAD_PATH")
    end
  end

  def test_doctor_jobs(dir, config, *argv, serial: true)
    FileUtils.mkdir_p(File.join(dir, "spec"))
    File.write(File.join(dir, "spec", "a_spec.rb"), "")
    File.write(File.join(dir, ".kimera.yml"), config)
    allow(Kimera::Execution::SUITE).to(receive(:call)) do |_env, *command, **|
      ["", instance_double(Process::Status, success?: serial || command.include?("--dry-run"))]
    end
    test_doctor_in(dir, "--check-baseline", *argv).last
  end

  # A suite that is green in one process can still be red on the configured
  # workers; doctor runs it split across that many processes too.
  it "runs the baseline split across the configured jobs only when it is green serially", :aggregate_failures do
    parallel = "✓ Parallel baseline: green split across 3 processes too " \
      "(jobs: 3; #{Kimera::CLI::TestCommand::SAMPLE})\n"
    Dir.mktmpdir do |dir|
      expect(test_doctor_jobs(dir, "jobs: 3\n").lines.last).to(eq(parallel))
      expect(Kimera::Execution::SUITE).to(have_received(:call).exactly(5).times)
      expect(test_doctor_jobs(dir, "jobs: 3\n", "--jobs", "1")).not_to(include("Parallel"))
      expect(test_doctor_jobs(dir, "{}\n", "--jobs", "3").lines.last).to(eq(parallel))
      expect(test_doctor_jobs(dir, "jobs: 1\n")).not_to(include("Parallel"))
      expect(test_doctor_jobs(dir, "{}\n")).not_to(include("Parallel"))
      expect(test_doctor_jobs(dir, "jobs: many\n")).not_to(include("Parallel"))
      expect(test_doctor_jobs(dir, "jobs:\n")).not_to(include("Parallel"))
      red = test_doctor_jobs(dir, "jobs: 3\n", serial: false)
      expect(red).to(include("✗ Baseline"))
      expect(red).not_to(include("Parallel"))
    end
  end

  # thor keeps its floor in spec/helper.rb.
  it "finds a coverage floor in any spec or test helper" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "spec", "support"))
      File.write(File.join(dir, "spec", "helper.rb"), "SimpleCov.start { minimum_coverage(90) }\n")
      expect(test_doctor_in(dir).last).to(include("! Coverage floor: minimum_coverage in spec/helper.rb"))
    end
  end

  # A .simplecov symlinked to a shared config that isn't checked out.
  it "passes over a helper path that is not a readable file" do
    Dir.mktmpdir do |dir|
      File.symlink(File.join(dir, "missing.rb"), File.join(dir, ".simplecov"))
      expect(test_doctor_in(dir).last).not_to(include("Coverage floor"))
    end
  end

  it "adds strict CI defaults without replacing explicit user choices" do
    out, error = captured
    runner = instance_double(Kimera::CLI::Run, run: 0)
    allow(Kimera::CLI::Run).to(receive(:new).and_return(runner))
    Kimera::CLI::CI.new(io: out, errors: error, env: {}).run(["--format", "sarif", "--max-survivors", "2"])
    expect(runner).to(
      have_received(:run).with(
        eq(["--format", "sarif", "--max-survivors", "2", "--fail-on-no-coverage"])
      )
    )
  end

  it "mutates a pull request's changed lines and summarizes the job when GitHub Actions says how" do
    out, error = captured
    runner = instance_double(Kimera::CLI::Run, run: 0)
    allow(Kimera::CLI::Run).to(receive(:new).and_return(runner))
    env = { "GITHUB_BASE_REF" => "main", "GITHUB_STEP_SUMMARY" => "/tmp/step.md" }
    Kimera::CLI::CI.new(io: out, errors: error, env: env).run([])
    expect(runner).to(have_received(:run).with(include("--since", "origin/main", "--summary", "/tmp/step.md")))
  end

  it "leaves an explicit --since and --summary alone, and an empty environment variable unused", :aggregate_failures do
    out, error = captured
    runner = instance_double(Kimera::CLI::Run, run: 0)
    allow(Kimera::CLI::Run).to(receive(:new).and_return(runner))
    env = { "GITHUB_BASE_REF" => "main", "GITHUB_STEP_SUMMARY" => "/tmp/step.md" }
    Kimera::CLI::CI.new(io: out, errors: error, env: env).run(["--since", "HEAD~1", "--summary=s.md"])
    Kimera::CLI::CI.new(io: out, errors: error, env: { "GITHUB_BASE_REF" => "", "GITHUB_STEP_SUMMARY" => "" }).run([])
    expect(runner).not_to(have_received(:run).with(include("origin/main")))
    expect(runner).not_to(have_received(:run).with(include("/tmp/step.md")))
    expect(runner).not_to(have_received(:run).with(include("--summary")))
  end

  it "preserves equals-form CI overrides" do
    out, error = captured
    runner = instance_double(Kimera::CLI::Run, run: 0)
    allow(Kimera::CLI::Run).to(receive(:new).and_return(runner))
    Kimera::CLI::CI.new(
      io: out, errors: error,
      env: {}
    ).run(["--format=sarif", "--max-survivors=2", "--report=out.json"])
    expect(runner).to(have_received(:run).with(include("--format=sarif", "--max-survivors=2", "--report=out.json")))
    expect(runner).not_to(have_received(:run).with(include("github")))
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
    out, error = captured
    expect(Kimera::CLI::CI.new(io: out, errors: error, env: {}).run(["--help"])).to(eq(0))
    expect(out.string).to(start_with("Usage: kimera ci [paths...] [options]\nkimera run with gate defaults"))
    expect(out.string).to(include("--judge-isolated-only"))
  end

  # The report's run section records what the run did, not the raw flag.
  it "records the effective survivor confirmation and DSL judging", :aggregate_failures do
    effective =
      lambda do |options|
        Kimera::CLI::Run::Cycle.new(options, nil, digest: nil).__send__(:provenance)
          .slice("judge_isolated_only", "confirm_survivors")
      end
    expect(effective.call(since: "HEAD~1")).to(eq("judge_isolated_only" => true, "confirm_survivors" => true))
    expect(effective.call({})).to(eq("judge_isolated_only" => false, "confirm_survivors" => false))
    expect(effective.call(since: "HEAD~1", confirm_survivors: false)).to(include("confirm_survivors" => false))
  end

  it "prints shell completion scripts and a command suggestion" do
    out, error = captured
    expect(Kimera::CLI::Completion.new(io: out, errors: error).run(["bash"])).to(eq(0))
    expect(out.string).to(include("complete -F _kimera kimera", "changed", " report "))
    expect(out.string).not_to(match(/\b(dump|survivors)\b/))
    expect(described_class.new(io: out, errors: error).run(["rn"])).to(eq(1))
    expect(error.string).to(include('did you mean "run"?', "Try: kimera help"))
  end

  it "creates and reviews an explicit, reasoned baseline" do
    Dir.mktmpdir do |dir|
      report = written(dir, "results" => [survivor])
      baseline = File.join(dir, "baseline.yml")
      out, error = captured
      cli = Kimera::CLI::Baseline.new(io: out, errors: error)
      created = Dir.chdir(dir) { cli.run(["create", report, "--reason", "adoption debt", "--output", baseline]) }
      expect(created).to(eq(0))
      expect(YAML.safe_load_file(baseline).fetch("ignore").first).to(include("reason" => "adoption debt"))
      expect(cli.run(["review", baseline])).to(eq(0))
      expect(out.string).to(include("1 accepted mutant(s)", "app/a.rb:3 [> => >=] — adoption debt"))
    end
  end

  it "rejects an unknown baseline subcommand" do
    out, error = captured
    status = Kimera::CLI::Baseline.new(io: out, errors: error).run(["unknown"])
    expect(status).to(eq(1))
    expect(error.string).to(include('kimera: unknown baseline command "unknown"', "Usage: kimera baseline <command>"))
    expect(Kimera::CLI::Baseline.new(io: out, errors: error).run([])).to(eq(1))
    expect(error.string).to(include("kimera: missing command\n"))
  end

  it "prints the baseline commands for --help, -h and help", :aggregate_failures do
    %w[--help -h help].each do |flag|
      out, error = captured
      expect(Kimera::CLI::Baseline.new(io: out, errors: error).run([flag])).to(eq(0))
      expect(out.string).to(start_with("Usage: kimera baseline <command> [options]\n"))
      commands = ["create [REPORT.json] --reason TEXT [--write]", "review BASELINE.yml", "prune BASELINE.yml"]
      expect(out.string).to(include(*commands))
    end
  end

  it "sets the new baseline in .kimera.yml under --write, replacing a commented or earlier line", :aggregate_failures do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        report = written(dir, "results" => [survivor.merge("line" => 3, "label" => "> => >=")])
        File.write(".kimera.yml", "jobs: 2\n# baseline: old.yml\n")
        out, error = captured
        cli = Kimera::CLI::Baseline.new(io: out, errors: error)
        expect(cli.run(["create", report, "--reason", "adopting", "--write"])).to(eq(0))
        expect(File.read(".kimera.yml")).to(eq("jobs: 2\nbaseline: .kimera-baseline.yml\n"))
        expect(out.string).to(include("Set `baseline: .kimera-baseline.yml` in .kimera.yml."))
        File.write(".kimera.yml", "jobs: 2")
        cli.run(["create", report, "--reason", "adopting", "--write", "--force", "--output", "b.yml"])
        expect(File.read(".kimera.yml")).to(eq("jobs: 2\nbaseline: b.yml\n"))
      end
    end
  end

  it "refuses --write without a .kimera.yml, and reads the default report", :aggregate_failures do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p("tmp/kimera")
        File.write("tmp/kimera/report.json", JSON.generate("results" => [survivor.merge("line" => 3, "label" => "x")]))
        out, error = captured
        expect(Kimera::CLI::Baseline.new(io: out, errors: error).run(%w[create --reason adopting --write])).to(eq(1))
        expect(error.string).to(include("no .kimera.yml to set the baseline in (run kimera init first)"))
        expect(File.read(".kimera-baseline.yml")).to(include("file: app/a.rb"))
      end
    end
  end

  it "uses report as the friendly survivors alias and mutant as focused detail" do
    Dir.mktmpdir do |dir|
      report = written(dir, "results" => [survivor])
      out, error = captured
      cli = described_class.new(io: out, errors: error)
      expect(cli.run(["report", report])).to(eq(0))
      expect(cli.run(["mutant", "7", "--report", report])).to(eq(0))
      expect(out.string).to(include("1 survived mutant(s):", "#7  survived  app/a.rb:3\n"))
    end
  end

  it "finds a mutant by its key and shows the key in place of file:line" do
    Dir.mktmpdir do |dir|
      report = written(dir, "results" => [survivor.merge("key" => "app/a.rb:3:0123abcd")])
      out, error = captured
      cli = described_class.new(io: out, errors: error)
      expect(cli.run(["mutant", "app/a.rb:3:0123abcd", "--report", report])).to(eq(0))
      expect(cli.run(["report", report])).to(eq(0))
      expect(out.string).to(include("#7  survived  app/a.rb:3:0123abcd\n", "  #7  app/a.rb:3:0123abcd  [> => >=]"))
      expect(out.string).to(include("detail: kimera mutant <ID|KEY> --report #{report}"))
      expect(cli.run(["mutant", "app/a.rb:3:ffffffff", "--report", report])).to(eq(1))
      expect(error.string).to(include("no mutant #app/a.rb:3:ffffffff in this report"))
    end
  end

  it "re-runs only the requested mutant" do
    Dir.mktmpdir do |dir|
      provenance = { "framework" => "rspec", "source_root" => ".", "tests" => ["spec/**/*_spec.rb"] }
        .merge("operators" => ["comparison"], "coverage" => true, "isolated" => false)
      row = survivor.slice("mutant_id", "status", "file").merge("key" => "app/a.rb:3:0123abcd")
      report = written(dir, "run" => provenance, "results" => [row])
      out, error = captured
      runner = instance_double(Kimera::CLI::Run, run: 2)
      allow(Kimera::CLI::Run).to(receive(:new).and_return(runner))
      status = Kimera::CLI::Mutant.new(io: out, errors: error).run(["7", "--report", report, "--rerun"])
      expect(status).to(eq(2))
      expect(runner).to(
        have_received(:run).with(
          ["app/a.rb", "--focus", "app/a.rb:3:0123abcd", "--framework", "rspec", "--source-root", "."]
            .push("--tests", "spec/**/*_spec.rb", "--operators", "comparison", "--no-report")
        )
      )
      expect(out.string).to(eq("Re-running mutant #7: app/a.rb:3:0123abcd\n"))
    end
  end

  it "evaluates an ignored mutant when re-running it" do
    Dir.mktmpdir do |dir|
      provenance = { "framework" => "rspec", "source_root" => ".", "tests" => ["spec/**/*_spec.rb"] }
        .merge("operators" => ["comparison"], "coverage" => true, "isolated" => false)
      row = { "mutant_id" => 7, "status" => "ignored", "file" => "app/a.rb", "key" => "app/a.rb:3:0123abcd" }
      report = written(dir, "run" => provenance, "results" => [row])
      out, error = captured
      runner = instance_double(Kimera::CLI::Run, run: 0)
      allow(Kimera::CLI::Run).to(receive(:new).and_return(runner))
      Kimera::CLI::Mutant.new(io: out, errors: error).run(["7", "--report", report, "--rerun"])
      expect(runner).to(have_received(:run).with(array_including("--evaluate-ignored")))
    end
  end
end
