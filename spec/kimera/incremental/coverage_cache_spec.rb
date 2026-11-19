# frozen_string_literal: true

require "fileutils"
require "json"
require "kimera/incremental/coverage_cache"
require "kimera/registry/builder"
require "stringio"
require "tmpdir"

using PointFields

RSpec.describe(Kimera::Incremental::CoverageCache) do
  let(:errors) { StringIO.new }
  let(:registry) { Kimera::RegistryScan.new.build(%w[lib/a.rb lib/b.rb lib/c.rb]) }
  let(:full) { { source_root: ".", paths: ["lib/*.rb"], tests: ["spec/*_spec.rb"] } }
  let(:map) { "tmp/kimera/coverage.json" }
  let(:narrowed) { { paths: ["lib/b.rb"], configured_paths: ["lib/*.rb"] } }

  around { |example| Dir.mktmpdir("kimera-cache") { |root| Dir.chdir(root) { example.run } } }

  before do
    %w[a b c].each { |name| write("lib/#{name}.rb", "def #{name}(x) = x > 1\n") }
    write("spec/a_spec.rb", "")
  end

  def write(path, body)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
  end

  def cache(scope: registry, **options)
    sources = ->(key) { Dir.glob(full.merge(configured_paths: ["lib/*.rb"]).merge(options).fetch(key)) }
    described_class.new(registry: scope, options: full.merge(options), sources: sources, errors: errors)
  end

  def ids(file) = registry.to_h.fetch(file, []).flat_map(&:ids)

  def harness
    Struct.new(:coverage).new({ ids("lib/a.rb").first => %w[t1], ids("lib/b.rb").last => %w[t2 t1], 999 => %w[t3] })
  end

  def adapter
    Struct.new(:test_ids) { def [](id) = Struct.new(:file).new("./spec/#{id}_spec.rb") }.new(%w[t1 t2 t3])
  end

  def keep(**) = cache(reuse_coverage: true, **).keep(harness, adapter)

  def changed(*files) = Kimera::Registry.new(files: registry.to_h.slice(*files))

  def reuse(scope = changed("lib/c.rb"))
    cache(scope: scope, reuse_coverage: true, since: "HEAD").measured(%w[t1 t2 t3 t4])
  end

  it "stores, after a full run, which tests reached each source file, and every test" do
    keep
    expect(JSON.parse(File.read(map)).values_at("coverage", "tests"))
      .to(eq([{ "lib/a.rb" => %w[t1], "lib/b.rb" => %w[t2 t1] }, %w[t1 t2 t3]]))
  end

  it "stores the file each test lives in, so a later run can tell which tests a change touched" do
    keep
    expect(JSON.parse(File.read(map))["test_files"])
      .to(eq("t1" => "spec/t1_spec.rb", "t2" => "spec/t2_spec.rb", "t3" => "spec/t3_spec.rb"))
  end

  it "stores nothing without --reuse-coverage, or on an incremental run", :aggregate_failures do
    cache.keep(harness, nil)
    keep(since: "HEAD")
    expect(File).not_to(exist(map))
  end

  it "measures every test without --reuse-coverage, or on a full run, saying nothing", :aggregate_failures do
    keep
    expect([cache(since: "HEAD"), cache(reuse_coverage: true)].map { |each| each.measured(%w[t1 t9]) })
      .to(eq([%w[t1 t9]] * 2))
    expect(errors.string).to(eq(""))
  end

  it "reruns the tests that reached a source file changed since, or one in scope, and the tests it never saw" do
    keep
    write("lib/a.rb", "def a(x) = x >= 1\n")
    expect(reuse).to(eq(%w[t1 t4]))
  end

  it "reruns the tests that reached an in-scope file, saying where the map came from and how much it saves" do
    keep
    reuse(changed("lib/b.rb"))
    expect(errors.string).to(
      eq(
        "kimera: reusing the coverage map from  (0 source and 0 test file(s) changed since): " \
          "the baseline runs 3 of 4 tests\n"
      )
    )
  end

  it "runs every test, saying nothing, when no map is stored" do
    expect([reuse, errors.string]).to(eq([%w[t1 t2 t3 t4], ""]))
  end

  it "runs every test, saying why, when the map is not JSON" do
    write("tmp/kimera/coverage.json", "{")
    reuse
    expect(errors.string).to(include("not reusing the stored coverage map: tmp/kimera/coverage.json is not JSON;"))
  end

  it "runs every test, naming the file, when a support file changed since" do
    keep
    write("spec/helper.rb", "changed")
    expect([reuse.size, errors.string]).to(
      eq([4, "kimera: not reusing the stored coverage map: spec/helper.rb changed; the baseline runs every test\n"])
    )
  end

  it "reruns only the tests an edited test file holds, beside those of the scope" do
    write("spec/t2_spec.rb", "")
    keep
    write("spec/t2_spec.rb", "changed")
    expect(reuse).to(eq(%w[t2 t4]))
  end

  it "runs every test when an edited test file defines shared examples, which other files may run" do
    write("spec/t2_spec.rb", "")
    keep
    write("spec/t2_spec.rb", "RSpec.shared_examples(\"x\") {}")
    expect([reuse.size, errors.string]).to(match([4, include("spec/t2_spec.rb changed")]))
  end

  it "reads the map on a run narrowed to some of the configured paths, and stores none from it", :aggregate_failures do
    keep(configured_paths: ["lib/*.rb"])
    write("lib/a.rb", "def a(x) = x >= 1\n")
    keep(**narrowed)
    expect(cache(scope: changed("lib/b.rb"), reuse_coverage: true, **narrowed).measured(%w[t1 t2 t3])).to(eq(%w[t1 t2]))
    expect(JSON.parse(File.read(map))["sources"]["lib/a.rb"]).not_to(eq(Digest::SHA256.hexdigest(File.read("lib/a.rb"))))
  end

  it "runs every test when a file in scope lies outside the configured paths the map covers" do
    keep
    write("other/d.rb", "def d(x) = x > 1\n")
    scope = Kimera::RegistryScan.new.build(%w[other/d.rb])
    expect(cache(scope: scope, reuse_coverage: true, since: "HEAD").measured(%w[t1 t2]).size).to(eq(2))
  end
end
