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
    [out.string, error.string, described_class.new.run(argv)]
  ensure
    $stdout = output
    $stderr = errors
  end

  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
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

  attr_reader :dir

  def catalog(file: "calc.rb")
    Kimera::RegistryScan.new.source("def m(a, b)\n  a > b\nend\n", file: file)
  end

  it "requires --out and returns 1 without it" do
    _out, error, status = run("calc.rb")
    expect(error).to(include("kimera synthesize: --out DIR is required"))
    expect(status).to(eq(1))
  end

  # `x > y` yields `>=` and `<` under the default operators.
  it "synthesizes a mirror tree and reports exact schema-path counts" do
    out, _error, status = run("calc.rb", "--out", outdir = File.join(dir, "schemata"))
    expect(status).to(eq(0))
    expect(out).to(eq("Synthesized 1 files to #{outdir}.\n  2 mutants on the schema path.\n"))
    expect(File.read(File.join(outdir, "calc.rb"))).to(include("active?"))
  end

  it "falls back to the default globs when no paths are given" do
    Dir.mkdir(File.join(dir, "lib"))
    File.write(File.join(dir, "lib", "deep.rb"), "def m(a, b)\n  a > b\nend\n")
    out, _error, status = run("--out", File.join(dir, "out"))
    expect(status).to(eq(0))
    # calc.rb is outside the default globs.
    expect(out).to(include("Synthesized 1 files"))
  end

  it "skips registry entries whose source file is missing from disk" do
    manifest = File.join(dir, "reg.json")
    catalog(file: "ghost.rb").write(manifest)
    out, _error, status = run("--registry", manifest, "--out", File.join(dir, "out"))
    expect(status).to(eq(0))
    expect(out).to(include("0 mutants on the schema path."))
  end

  it "reports reload-fallback mutants when a memoized point is present" do
    File.write(File.join(dir, "memo.rb"), <<~RUBY)
      class Memo
        def total(a, b)
          @total ||= compute(a > b)
        end
      end
    RUBY
    out, = run("memo.rb", "--out", File.join(dir, "out"))
    expect(out).to(include("2 mutants routed to reload fallback (memoization)."))
  end

  def configuration
    Dir.mkdir(File.join(dir, "lib"))
    File.write(File.join(dir, "lib", "deep.rb"), "def m(a, b)\n  a > b\nend\n")
    File.write(File.join(dir, "lib", "skipped.rb"), "def m(a, b)\n  a > b\nend\n")
    File.write(File.join(dir, ".kimera.yml"), <<~YAML)
      paths: ["lib/**/*.rb"]
      exclude: ["lib/skipped.rb"]
      operators: [comparison]
    YAML
  end

  it "takes its scope from .kimera.yml" do
    configuration
    out, _error, status = run("--out", File.join(dir, "out"))
    expect(status).to(eq(0))
    expect(out).to(include("Synthesized 1 files", "2 mutants on the schema path."))
  end

  it "splits --operators into keys when building the registry" do
    outdir = File.join(dir, "ops")
    # calc.rb has no regexp literals.
    out, _error, status = run("calc.rb", "--operators", "regexp", "--out", outdir)
    expect(status).to(eq(0))
    expect(out).to(include("0 mutants on the schema path."))
  end

  it "loads an existing registry with --registry instead of building" do
    manifest = File.join(dir, "reg.json")
    catalog.write(manifest)
    out, _error, status = run("--registry", manifest, "--out", File.join(dir, "out"))
    expect(status).to(eq(0))
    expect(out).to(include("Synthesized 1 files"))
  end
end
