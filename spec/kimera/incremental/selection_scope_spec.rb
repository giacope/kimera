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

  around { |example| Dir.mktmpdir("kimera-scope") { |root| Dir.chdir(root) { example.run } } }

  before do
    git("init", "-q", "-b", "main")
    write("lib/calc.rb", "def a(x, y)\n  x > y\nend\n\ndef b(x)\n  x < 1\nend\n")
    write("lib/other.rb", "def c(x)\n  x >= 2\nend\n")
    write("spec/other_spec.rb", "it { c(1) }\n")
    git("add", "-A")
    git(*%w[-c user.email=t@example.com -c user.name=Test -c commit.gpgsign=false commit -q -m a])
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

  def mapped(test_files: { "./spec/other_spec.rb[1:1]" => "./spec/other_spec.rb" })
    map = { "coverage" => { "lib/other.rb" => ["./spec/other_spec.rb[1:1]"] }, "test_files" => test_files }
    write("tmp/kimera/coverage.json", JSON.generate(map))
  end

  it "keeps the changed lines by default, and every line of each changed file with files", :aggregate_failures do
    write("lib/calc.rb", "def a(x, y)\n  x < y\nend\n\ndef b(x)\n  x < 1\nend\n")
    expect(selected("lines")).to(eq(["x < y"]))
    expect(selected("files")).to(include("x < y", "x < 1"))
    expect(selected("files")).not_to(include("x >= 2"))
  end

  it "keeps a file whose change only deletes lines, which has no changed line to select" do
    write("lib/calc.rb", "def a(x, y)\n  x > y\nend\n")
    expect([selected("lines"), selected("files")]).to(eq([[], ["x > y"]]))
  end

  it "keeps, with impact, the files the coverage map says a changed test reached", :aggregate_failures do
    mapped
    write("spec/other_spec.rb", "it { c(2) }\n")
    expect(selected("files")).to(eq([]))
    expect(selected("impact")).to(eq(["x >= 2"]))
  end

  it "reads a test's file stored as an absolute path, as Minitest's source location gives it" do
    mapped(test_files: { "./spec/other_spec.rb[1:1]" => File.expand_path("spec/other_spec.rb") })
    write("spec/other_spec.rb", "it { c(2) }\n")
    expect(selected("impact")).to(eq(["x >= 2"]))
  end

  it "counts a deleted test as changed, so the files it reached stay in scope" do
    mapped
    FileUtils.rm("spec/other_spec.rb")
    expect(selected("impact")).to(eq(["x >= 2"]))
  end

  it "keeps only the changed files with impact when no map is stored, and says how to store one", :aggregate_failures do
    write("spec/other_spec.rb", "it { c(2) }\n")
    expect(selected("impact")).to(eq([]))
    expect(errors.string).to(include("no coverage map is stored at tmp/kimera/coverage.json", "--reuse-coverage"))
  end

  it "says so when the stored map names no test's file, as one from an older kimera", :aggregate_failures do
    write("tmp/kimera/coverage.json", JSON.generate("coverage" => { "lib/other.rb" => ["t1"] }))
    write("spec/other_spec.rb", "it { c(2) }\n")
    expect(selected("impact")).to(eq([]))
    expect(errors.string).to(include("names no test's file"))
  end

  it "says so when the stored map is not JSON", :aggregate_failures do
    write("tmp/kimera/coverage.json", "{")
    expect(selected("impact")).to(eq([]))
    expect(errors.string).to(include("tmp/kimera/coverage.json is not JSON"))
  end

  it "reads the scope from .from_diff, in the root given" do
    write("lib/calc.rb", "def a(x, y)\n  x < y\nend\n\ndef b(x)\n  x < 1\nend\n")
    ids = selection("files").ids(registry)
    expect(ids.map { |id| registry.index[id].original_source }.uniq).to(include("x < y", "x < 1"))
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
    expect(%w[lines files impact].map { announced(it) }).to(eq(said))
  end
end
