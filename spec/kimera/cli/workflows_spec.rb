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

RSpec.describe("Kimera guided CLI workflows", :aggregate_failures) do
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

  it "points AI agents to kimera skill in AGENTS.md exactly once" do
    Dir.mktmpdir do |dir|
      agents = File.join(dir, "AGENTS.md")
      File.write(agents, "# Agents\n\n")
      out, error = captured
      Kimera::CLI::Init.new(io: out, errors: error, root: dir).run([])
      expect(File.read(agents)).to(eq("# Agents\n\n#{Kimera::CLI::Init::AGENT_POINTER}"))
      expect(out.string).to(include("Pointed AI agents to `kimera skill` in AGENTS.md."))
      again = StringIO.new
      Kimera::CLI::Init.new(io: again, errors: error, root: dir).run(["--force"])
      expect(File.read(agents).scan("kimera skill").size).to(eq(1))
      expect(again.string).not_to(include("AGENTS.md"))
    end
  end

  it "creates AGENTS.md with only the pointer when the project has none" do
    Dir.mktmpdir do |dir|
      out, error = captured
      Kimera::CLI::Init.new(io: out, errors: error, root: dir).run([])
      expect(File.read(File.join(dir, "AGENTS.md"))).to(eq(Kimera::CLI::Init::AGENT_POINTER))
      Kimera::CLI::Init.new(io: out, errors: error, root: File.join(dir, "preview")).run(["--dry-run"])
      expect(File).not_to(exist(File.join(dir, "preview", "AGENTS.md")))
    end
  end

  it "prints the bundled agent skill and rejects arguments" do
    out, error = captured
    expect(Kimera::CLI.new(io: out, errors: error).run(["skill"])).to(eq(0))
    expect(out.string).to(eq(File.read(File.expand_path("../../../skills/kimera/SKILL.md", __dir__))))
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

  it "adds strict CI defaults without replacing explicit user choices" do
    out, error = captured
    runner = instance_double(Kimera::CLI::Run, run: 0)
    allow(Kimera::CLI::Run).to(receive(:new).and_return(runner))
    Kimera::CLI::CI.new(io: out, errors: error).run(["--format", "sarif", "--max-survivors", "2"])
    expect(runner).to(
      have_received(:run).with(
        include("--format", "sarif", "--max-survivors", "2", "--fail-on-no-coverage")
          .and(include("--report", "tmp/kimera/report.json"))
      )
    )
  end

  it "preserves equals-form CI overrides" do
    out, error = captured
    runner = instance_double(Kimera::CLI::Run, run: 0)
    allow(Kimera::CLI::Run).to(receive(:new).and_return(runner))
    Kimera::CLI::CI.new(io: out, errors: error).run(["--format=sarif", "--max-survivors=2", "--report=out.json"])
    expect(runner).to(have_received(:run).with(include("--format=sarif", "--max-survivors=2", "--report=out.json")))
    expect(runner).not_to(have_received(:run).with(include("github")))
  end

  it "prints shell completion scripts and a command suggestion" do
    out, error = captured
    expect(Kimera::CLI::Completion.new(io: out, errors: error).run(["bash"])).to(eq(0))
    expect(out.string).to(include("complete -F _kimera kimera", "changed"))
    expect(Kimera::CLI.new(io: out, errors: error).run(["rn"])).to(eq(1))
    expect(error.string).to(include('did you mean "run"?', "Try: kimera help"))
  end

  it "creates and reviews an explicit, reasoned baseline" do
    Dir.mktmpdir do |dir|
      report = written(dir, "results" => [survivor])
      baseline = File.join(dir, "baseline.yml")
      out, error = captured
      cli = Kimera::CLI::Baseline.new(io: out, errors: error)
      expect(cli.run(["create", report, "--reason", "adoption debt", "--output", baseline])).to(eq(0))
      expect(YAML.safe_load_file(baseline).fetch("ignore").first).to(include("reason" => "adoption debt"))
      expect(cli.run(["review", baseline])).to(eq(0))
      expect(out.string).to(include("1 accepted mutant(s)", "app/a.rb:3 [> => >=] — adoption debt"))
    end
  end

  it "rejects an unknown baseline subcommand" do
    out, error = captured
    status = Kimera::CLI::Baseline.new(io: out, errors: error).run(["unknown"])
    expect(status).to(eq(1))
    expect(error.string).to(include("usage: kimera baseline <create|review|prune> ..."))
  end

  it "uses report as the friendly survivors alias and mutant as focused detail" do
    Dir.mktmpdir do |dir|
      report = written(dir, "results" => [survivor])
      out, error = captured
      cli = Kimera::CLI.new(io: out, errors: error)
      expect(cli.run(["report", report])).to(eq(0))
      expect(cli.run(["mutant", "7", "--report", report])).to(eq(0))
      expect(out.string).to(include("1 survived mutant(s):", "#7  survived  app/a.rb:3\n"))
    end
  end

  it "finds a mutant by its key and shows the key in place of file:line" do
    Dir.mktmpdir do |dir|
      report = written(dir, "results" => [survivor.merge("key" => "app/a.rb:3:0123abcd")])
      out, error = captured
      cli = Kimera::CLI.new(io: out, errors: error)
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
            .push("--tests", "spec/**/*_spec.rb", "--operators", "comparison")
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
