# frozen_string_literal: true

require "fileutils"
require "json"
require "kimera/incremental/selection"
require "kimera/registry/builder"
require "open3"
require "stringio"
require "tmpdir"

using PointFields

RSpec.describe(Kimera::Incremental::Selection) do
  let(:errors) { StringIO.new }

  def project
    Dir.mktmpdir("kimera-scope") do |root|
      Dir.chdir(root) do
        git("init", "-q", "-b", "main")
        write("lib/calc.rb", "def a(x, y)\n  x > y\nend\n\ndef b(x)\n  x < 1\nend\n")
        write("lib/other.rb", "def c(x)\n  x >= 2\nend\n")
        write("spec/other_spec.rb", "it { c(1) }\n")
        git("add", "-A")
        git(*%w[-c user.email=t@example.com -c user.name=Test -c commit.gpgsign=false commit -q -m a])
        yield
      end
    end
  end

  def git(*arguments)
    _out, error, status = Open3.capture3("git", *arguments)
    raise(RuntimeError, "git #{arguments.join(" ")} failed: #{error}") unless status.success?
  end

  def write(path, body)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
  end

  def registry = Kimera::RegistryScan.new.build(%w[lib/calc.rb lib/other.rb])

  def selection(scope) = described_class.from_diff(since: "main", root: ".", scope: scope)

  def selected(scope)
    extent = Kimera::Incremental::Extent.new(scope, ".", errors: errors)
    picked = described_class.new(extent.changes(Kimera::Incremental::GitDiff.new(since: "main")), "main", extent)
    picked.ids(registry).map { |id| registry.index[id].original_source }.uniq
  end

  def picks(*scopes) = project { yield.then { scopes.map { selected(it) } } }

  def pick(scope, &) = picks(scope, &).first

  def test(name) = "./spec/#{name}_spec.rb[1:1]"

  def mapped(test_files: { test("other") => "./spec/other_spec.rb" }, coverage: { "lib/other.rb" => [test("other")] })
    write("tmp/kimera/coverage.json", JSON.generate("coverage" => coverage, "test_files" => test_files))
  end

  def both = %w[other calc].to_h { [test(it), "./spec/#{it}_spec.rb"] }

  def edited = write("lib/calc.rb", "def a(x, y)\n  x < y\nend\n\ndef b(x)\n  x < 1\nend\n")

  def touched = write("spec/other_spec.rb", "it { c(2) }\n")

  it "keeps the changed lines by default, and every line of each changed file with files", :aggregate_failures do
    lines, files = picks("lines", "files") { edited }
    expect(lines).to(eq(["x < y"]))
    expect(files).to(include("x < y", "x < 1"))
    expect(files).not_to(include("x >= 2"))
  end

  it "keeps a file whose change only deletes lines, which has no changed line to select" do
    found = picks("lines", "files") { write("lib/calc.rb", "def a(x, y)\n  x > y\nend\n") }
    expect(found).to(eq([[], ["x > y"]]))
  end

  it "keeps, with impact, the files the coverage map says a changed test reached", :aggregate_failures do
    files, impact = picks("files", "impact") { mapped && touched }
    expect(files).to(eq([]))
    expect(impact).to(eq(["x >= 2"]))
  end

  it "leaves out the files only the unchanged tests reach" do
    coverage = { "lib/other.rb" => [test("other")], "lib/calc.rb" => [test("calc")] }
    expect(pick("impact") { mapped(test_files: both, coverage: coverage) && touched }).to(eq(["x >= 2"]))
  end

  def absolute = { test("other") => File.expand_path("spec/other_spec.rb") }

  it "reads a test's file stored as an absolute path, as Minitest's source location gives it" do
    found = pick("impact") { mapped(test_files: absolute) && touched }
    expect(found).to(eq(["x >= 2"]))
  end

  it "counts a deleted test as changed, so the files it reached stay in scope" do
    expect(pick("impact") { mapped && FileUtils.rm("spec/other_spec.rb") }).to(eq(["x >= 2"]))
  end

  it "keeps only the changed files with impact when no map is stored, and says how to store one", :aggregate_failures do
    expect(pick("impact") { touched }).to(eq([]))
    expect(errors.string).to(include("no coverage map is stored at tmp/kimera/coverage.json", "a full run stores"))
    expect(errors.string.lines.size).to(eq(1))
  end

  def older = write("tmp/kimera/coverage.json", JSON.generate("coverage" => { "lib/other.rb" => ["t1"] }))

  it "says so when the stored map names no test's file, as one from an older kimera", :aggregate_failures do
    expect(pick("impact") { older && touched }).to(eq([]))
    expect(errors.string).to(include("names no test's file"))
  end

  it "says so when the stored map is not JSON", :aggregate_failures do
    expect(pick("impact") { write("tmp/kimera/coverage.json", "{") }).to(eq([]))
    expect(errors.string.lines).to(contain_exactly(a_string_including("tmp/kimera/coverage.json is not JSON")))
  end

  def chosen
    ids = selection("files").ids(registry)
    ids.map { |id| registry.index[id].original_source }.uniq
  end

  it "reads the scope from .from_diff, in the root given" do
    expect(project { edited && chosen }).to(include("x < y", "x < 1"))
  end

  def announced(scope)
    extent = Kimera::Incremental::Extent.new(scope)
    StringIO.new.tap { described_class.new({}, "main", extent).announce(it, [1, 2], 3) }.string
  end

  it "announces what each scope selected" do
    said = [
      "Incremental: 2 mutants on lines changed since main (3 changed files).\n",
      "Incremental: 2 mutants in the 3 files changed since main.\n",
      "Incremental: 2 mutants in 3 files changed since main or reached by the tests changed since.\n"
    ]
    expect(project { %w[lines files impact].map { announced(it) } }).to(eq(said))
  end
end
