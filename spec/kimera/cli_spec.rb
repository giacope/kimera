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
    [out.string, error.string, ended(described_class.new.run(argv), out, error)]
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
      expect(error).to(eq("kimera: invalid option: --nonsense\nTry: kimera registry --help\n"))
    end

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
      expect(error).to(eq("kimera: unknown command \"frobnicate\"\nTry: kimera help\n"))
      expect(out).to(eq(""))
      expect(status).to(eq(1))
    end

    def dispatch(argv, status = 0)
      handlers = FakeHandlers.new(status)
      [ended(described_class.new(handlers: handlers).run(argv), StringIO.new, StringIO.new), handlers.ran]
    end

    it "hands the synthesize subcommand to its file's handler" do
      expect(dispatch(["synthesize", "--out", "x"])).to(eq([0, [["synthesize", :Synthesize, ["--out", "x"]]]]))
    end

    it "hands the run subcommand to its file's handler, and answers its status" do
      expect(dispatch(%w[run app --jobs 2], 2)).to(eq([2, [["run", :Run, ["app", "--jobs", "2"]]]]))
    end

    it "hands the survivors subcommand to its file's handler" do
      expect(dispatch(["survivors", "r.json"])).to(eq([0, [["survivors", :Survivors, ["r.json"]]]]))
    end
  end

  describe "registry command" do
    def inside(&)
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "calc.rb"), <<~RUBY)
          class Calc
            def a(x, y)
              x > y
            end
          end
        RUBY
        Dir.chdir(dir, &)
      end
    end

    it "summarizes the registry by default, and only summarizes" do
      out, _error, status = inside { run("registry", "calc.rb") }
      expect(out).to(match(/\AFound \d+ mutants at \d+ mutation points across 1 files\.\n\z/))
      expect(status).to(eq(0))
    end

    def deep
      FileUtils.mkdir_p(File.join(Dir.pwd, "lib"))
      File.write(File.join(Dir.pwd, "lib", "deep.rb"), "def m(a, b)\n  a > b\nend\n")
    end

    def fallback
      deep
      run("registry")
    end

    it "falls back to the default globs when no paths are given" do
      out, _error, status = inside { fallback }
      expect(out).to(match(/\AFound \d+ mutants at \d+ mutation points across 1 files\.\n\z/))
      expect(status).to(eq(0))
    end

    def configuration
      deep
      File.write(File.join(Dir.pwd, "lib", "skipped.rb"), "def m(a, b)\n  a > b\nend\n")
      File.write(File.join(Dir.pwd, ".kimera.yml"), <<~YAML)
        paths: ["lib/**/*.rb"]
        exclude: ["lib/skipped.rb"]
        operators: [comparison]
      YAML
    end

    def scoped
      configuration
      run("registry")
    end

    it "takes its scope from .kimera.yml" do
      out, _error, status = inside { scoped }
      expect(out).to(eq("Found 2 mutants at 1 mutation points across 1 files.\n"))
      expect(status).to(eq(0))
    end

    def overridden
      File.write(File.join(Dir.pwd, ".kimera.yml"), "paths: [\"nothing/**/*.rb\"]\n")
      run("registry", "calc.rb")
    end

    it "lets a positional path override the configured one" do
      out, _error, status = inside { overridden }
      expect(out).to(match(/across 1 files\.\n\z/))
      expect(status).to(eq(0))
    end

    it "accepts `dump` as an alias for `registry`" do
      out, _error, status = inside { run("dump", "calc.rb") }
      expect(out).to(match(/\AFound \d+ mutants at \d+ mutation points across 1 files\.\n\z/))
      expect(status).to(eq(0))
    end

    it "stays silent with --quiet" do
      out, = inside { run("registry", "calc.rb", "--quiet") }
      expect(out).to(eq(""))
    end

    it "prints JSON with --json" do
      out, = inside { run("registry", "calc.rb", "--json", "--quiet") }
      parsed = JSON.parse(out)
      expect(parsed["points"]).to(be_an(Array))
    end

    def written
      path = File.join(Dir.pwd, "reg.json")
      out, = run("registry", "calc.rb", "--output", path)
      [out, path, File.exist?(path)]
    end

    it "writes the registry to a file with --output and reports it" do
      out, path, exists = inside { written }
      expect(exists).to(be(true))
      expect(out).to(include("Wrote registry to #{path}"))
    end

    it "honors --operators, splitting a comma list into a restricted set" do
      out, = inside { run("registry", "calc.rb", "--operators", "comparison,boolean_literal", "--json", "--quiet") }
      operators = JSON.parse(out)["operators"]
      expect(operators).to(eq(%w[comparison boolean_literal]))
    end

    it "warns with the given paths when no files match" do
      _out, error, status = inside { run("registry", "nope_a/**/*.rb", "nope_b/**/*.rb") }
      expect(error).to(include("kimera: no Ruby files matched nope_a/**/*.rb, nope_b/**/*.rb"))
      expect(status).to(eq(1))
    end

    it "warns with the default globs when no paths are given and none match" do
      _out, error, status = inside { run("registry") }
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
      expect { inside { described_class.new.run(["registry", "--help"]) } }.to(raise_error(SystemExit).and(matcher))
    end
  end
end
