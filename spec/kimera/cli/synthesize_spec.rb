# frozen_string_literal: true

require "kimera/cli/synthesize"
require "stringio"
require "tmpdir"

RSpec.describe(Kimera::CLI::Synthesize, :aggregate_failures) do
  def run(*argv)
    out = StringIO.new
    error = StringIO.new
    output = $stdout
    errors = $stderr
    $stdout = out
    $stderr = error
    [out.string, error.string, ended(described_class.new.run(argv), out, error)]
  ensure
    $stdout = output
    $stderr = errors
  end

  def inside
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "calc.rb"), <<~RUBY)
        class Calc
          def a(x, y)
            x > y
          end
        end
      RUBY
      Dir.chdir(dir) { yield(dir) }
    end
  end

  def catalog(file: "calc.rb")
    Kimera::RegistryScan.new.source("def m(a, b)\n  a > b\nend\n", file: file)
  end

  def manifest(dir, registry)
    File.join(dir, "reg.json").tap { |path| File.write(path, JSON.pretty_generate(registry)) }
  end

  def deep(dir)
    Dir.mkdir(File.join(dir, "lib"))
    File.write(File.join(dir, "lib", "deep.rb"), "def m(a, b)\n  a > b\nend\n")
  end

  it "requires --out and returns 1 without it" do
    _out, error, status = inside { run("calc.rb") }
    expect(error).to(include("kimera synthesize: --out DIR is required"))
    expect(status).to(eq(1))
  end

  it "synthesizes a mirror tree and reports exact schema-path counts" do
    inside do |dir|
      out, _error, status = run("calc.rb", "--out", outdir = File.join(dir, "schemata"))
      expect([status, out]).to(eq([0, "Synthesized 1 files to #{outdir}.\n  2 mutants on the schema path.\n"]))
      expect(File.read(File.join(outdir, "calc.rb"))).to(include("active?"))
    end
  end

  def fallback(dir)
    deep(dir)
    run("--out", File.join(dir, "out"))
  end

  it "falls back to the default globs when no paths are given" do
    out, _error, status = inside { |dir| fallback(dir) }
    expect([status, out]).to(match([0, include("Synthesized 1 files")]))
  end

  it "skips registry entries whose source file is missing from disk" do
    out, _error, status = inside { |dir| run("--registry", manifest(dir, catalog(file: "ghost.rb")), "--out", "out") }
    expect(status).to(eq(0))
    expect(out).to(include("0 mutants on the schema path."))
  end

  def memoized(dir)
    File.write(File.join(dir, "memo.rb"), <<~RUBY)
      class Memo
        def total(a, b)
          @total ||= compute(a > b)
        end
      end
    RUBY
    run("memo.rb", "--out", File.join(dir, "out"))
  end

  it "reports reload-fallback mutants when a memoized point is present" do
    out, = inside { |dir| memoized(dir) }
    expect(out).to(include("2 mutants routed to reload fallback (memoization)."))
  end

  def configuration(dir)
    deep(dir)
    File.write(File.join(dir, "lib", "skipped.rb"), "def m(a, b)\n  a > b\nend\n")
    File.write(File.join(dir, ".kimera.yml"), <<~YAML)
      paths: ["lib/**/*.rb"]
      exclude: ["lib/skipped.rb"]
      operators: [comparison]
    YAML
  end

  def scoped(dir)
    configuration(dir)
    run("--out", File.join(dir, "out"))
  end

  it "takes its scope from .kimera.yml" do
    out, _error, status = inside { |dir| scoped(dir) }
    expect([status, out]).to(match([0, include("Synthesized 1 files", "2 mutants on the schema path.")]))
  end

  it "splits --operators into keys when building the registry" do
    out, _error, status = inside { |dir| run("calc.rb", "--operators", "regexp", "--out", File.join(dir, "ops")) }
    expect(status).to(eq(0))
    expect(out).to(include("0 mutants on the schema path."))
  end

  it "loads an existing registry with --registry instead of building" do
    out, _error, status = inside { |dir| run("--registry", manifest(dir, catalog), "--out", File.join(dir, "out")) }
    expect(status).to(eq(0))
    expect(out).to(include("Synthesized 1 files"))
  end
end
