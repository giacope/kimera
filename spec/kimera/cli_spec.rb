# frozen_string_literal: true

require "fileutils"
require "kimera/cli"
require "kimera/cli/run"
require "kimera/cli/synthesize"
require "stringio"
require "tmpdir"

RSpec.describe(Kimera::CLI, :aggregate_failures) do
  def run(*argv)
    out = StringIO.new
    error = StringIO.new
    nil
    output = $stdout
    errors = $stderr
    $stdout = out
    $stderr = error
    [out.string, error.string, described_class.start(argv)]
  ensure
    $stdout = output
    $stderr = errors
  end

  describe "dispatch" do
    it "prints a one-line diagnosis for a usage error a subcommand does not rescue" do
      _out, error, status = run("registry", "--operators", "bogus_op", "lib")
      expect(status).to(eq(1))
      expect(error).to(start_with("kimera: unknown operator(s): bogus_op"))
    end

    it "prints usage, not a backtrace, for a mistyped flag" do
      _out, error, status = run("registry", "--nonsense")
      expect(status).to(eq(1))
      expect(error).to(include("kimera: invalid option: --nonsense", "Usage: kimera registry"))
    end

    # Exact match: the help banner also contains the version string.
    it "prints exactly the version for every version alias" do
      %w[version -v --version].each do |variant|
        out, _error, status = run(variant)
        expect(out).to(eq("kimera #{Kimera::VERSION}\n"))
        expect(status).to(eq(0))
      end
    end

    it "prints the full help for no command and every help alias" do
      ([[]] + %w[help -h --help].zip).each do |argv|
        out, _error, status = run(*argv)
        expect(out).to(include("Start here:", "kimera init && kimera doctor", "report REPORT.json", "completion SHELL"))
        expect(status).to(eq(0))
      end
    end

    it "warns and returns 1 on an unknown command" do
      out, error, status = run("frobnicate")
      expect(error).to(include('unknown command "frobnicate"'))
      expect(out).to(include("Usage: kimera <command>")) # falls through to help
      expect(status).to(eq(1))
    end

    def dispatch(klass, argv)
      cli = described_class.new
      allow(klass).to(receive(:new).and_return(instance_double(klass, run: 0)))
      allow(cli).to(receive(:require_relative))
      [cli, cli.run(argv)]
    end

    # In-process the files are already loaded, so pin the require itself.
    it "requires the synthesize subcommand file at dispatch" do
      cli, status = dispatch(Kimera::CLI::Synthesize, ["synthesize", "--out", "x"])
      expect(cli).to(have_received(:require_relative).with("cli/synthesize"))
      expect(status).to(eq(0))
    end

    it "requires the run subcommand file at dispatch" do
      cli, status = dispatch(Kimera::CLI::Run, ["run"])
      expect(cli).to(have_received(:require_relative).with("cli/run"))
      expect(status).to(eq(0))
    end

    it "requires the survivors subcommand file at dispatch" do
      require "kimera/cli/survivors"
      cli, status = dispatch(Kimera::CLI::Survivors, ["survivors", "r.json"])
      expect(cli).to(have_received(:require_relative).with("cli/survivors"))
      expect(status).to(eq(0))
    end

    it "delegates `synthesize` to the synthesis CLI" do
      delegate = instance_double(Kimera::CLI::Synthesize, run: 0)
      allow(Kimera::CLI::Synthesize).to(receive(:new).and_return(delegate))
      _out, _error, status = run("synthesize", "--out", "x")
      expect(delegate).to(have_received(:run).with(["--out", "x"]))
      expect(status).to(eq(0))
    end

    it "delegates `run` to the execution CLI" do
      delegate = instance_double(Kimera::CLI::Run, run: 2)
      allow(Kimera::CLI::Run).to(receive(:new).and_return(delegate))
      _out, _error, status = run("run", "app", "--jobs", "2")
      expect(delegate).to(have_received(:run).with(["app", "--jobs", "2"]))
      expect(status).to(eq(2))
    end
  end

  describe "registry command" do
    around do |example|
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "calc.rb"), <<~RUBY)
          class Calc
            def a(x, y)
              x > y
            end
          end
        RUBY
        Dir.chdir(dir) { example.run }
      end
    end

    it "summarizes the registry by default, and only summarizes" do
      out, _error, status = run("registry", "calc.rb")
      expect(out).to(match(/\AFound \d+ mutants at \d+ mutation points across 1 files\.\n\z/))
      expect(status).to(eq(0))
    end

    it "falls back to the default globs when no paths are given" do
      FileUtils.mkdir_p(File.join(Dir.pwd, "lib"))
      File.write(File.join(Dir.pwd, "lib", "deep.rb"), "def m(a, b)\n  a > b\nend\n")
      out, _error, status = run("registry")
      # calc.rb is outside the default globs.
      expect(out).to(match(/\AFound \d+ mutants at \d+ mutation points across 1 files\.\n\z/))
      expect(status).to(eq(0))
    end

    def configuration
      FileUtils.mkdir_p(File.join(Dir.pwd, "lib"))
      File.write(File.join(Dir.pwd, "lib", "deep.rb"), "def m(a, b)\n  a > b\nend\n")
      File.write(File.join(Dir.pwd, "lib", "skipped.rb"), "def m(a, b)\n  a > b\nend\n")
      File.write(File.join(Dir.pwd, ".kimera.yml"), <<~YAML)
        paths: ["lib/**/*.rb"]
        exclude: ["lib/skipped.rb"]
        operators: [comparison]
      YAML
    end

    it "takes its scope from .kimera.yml" do
      configuration
      out, _error, status = run("registry")
      # Only deep.rb's `a > b`, comparison only.
      expect(out).to(eq("Found 2 mutants at 1 mutation points across 1 files.\n"))
      expect(status).to(eq(0))
    end

    it "lets a positional path override the configured one" do
      File.write(File.join(Dir.pwd, ".kimera.yml"), "paths: [\"nothing/**/*.rb\"]\n")

      out, _error, status = run("registry", "calc.rb")

      expect(out).to(match(/across 1 files\.\n\z/))
      expect(status).to(eq(0))
    end

    it "accepts `dump` as an alias for `registry`" do
      out, _error, status = run("dump", "calc.rb")
      expect(out).to(match(/\AFound \d+ mutants at \d+ mutation points across 1 files\.\n\z/))
      expect(status).to(eq(0))
    end

    it "stays silent with --quiet" do
      out, = run("registry", "calc.rb", "--quiet")
      expect(out).to(eq(""))
    end

    it "prints JSON with --json" do
      out, = run("registry", "calc.rb", "--json", "--quiet")
      parsed = JSON.parse(out)
      expect(parsed["points"]).to(be_an(Array))
    end

    it "writes the registry to a file with --output and reports it" do
      path = File.join(Dir.pwd, "reg.json")
      out, = run("registry", "calc.rb", "--output", path)
      expect(File.exist?(path)).to(be(true))
      expect(out).to(include("Wrote registry to #{path}"))
    end

    it "honors --operators, splitting a comma list into a restricted set" do
      # Two keys, so the comma split is load-bearing.
      out, = run("registry", "calc.rb", "--operators", "comparison,boolean_literal", "--json", "--quiet")
      operators = JSON.parse(out)["operators"]
      expect(operators).to(eq(%w[comparison boolean_literal]))
    end

    it "warns with the given paths when no files match" do
      _out, error, status = run("registry", "nope_a/**/*.rb", "nope_b/**/*.rb")
      expect(error).to(include("kimera: no Ruby files matched nope_a/**/*.rb, nope_b/**/*.rb"))
      expect(status).to(eq(1))
    end

    it "warns with the default globs when no paths are given and none match" do
      _out, error, status = run("registry")
      expect(error).to(include("kimera: no Ruby files matched app/**/*.rb, lib/**/*.rb"))
      expect(status).to(eq(1))
    end

    def snippets
      [
        "Usage: kimera registry [paths...] [options]", "-o, --output FILE", "Write registry JSON to FILE",
        "Operator keys, or 'all'/'rails'", "Print registry JSON to stdout", "-q, --quiet",
        "Suppress the summary line"
      ]
    end

    it "documents every registry flag in --help" do
      matcher = output(include(*snippets)).to_stdout
      expect { described_class.start(["registry", "--help"]) }.to(raise_error(SystemExit).and(matcher))
    end
  end
end
