# frozen_string_literal: true

require "kimera/incremental/coverage_map"
require "tmpdir"

RSpec.describe(Kimera::Incremental::CoverageMap) do
  let(:current) do
    { "commit" => "0123456789abcdef", "ruby" => "ruby 4.0.7", "settings" => "s1" }
      .merge("files" => { "spec/a_spec.rb" => "a", "spec/b_spec.rb" => "b", ".rspec" => "r" })
      .merge("sources" => { "lib/a.rb" => "1", "lib/b.rb" => "2" })
  end
  let(:stored) do
    coverage = { "lib/a.rb" => %w[t1 t2], "lib/b.rb" => %w[t3] }
    files = { "t1" => "spec/a_spec.rb", "t2" => "spec/a_spec.rb", "t3" => "spec/b_spec.rb", "t4" => "spec/b_spec.rb" }
    measured = { "format" => 2, "coverage" => coverage, "tests" => %w[t1 t2 t3 t4], "test_files" => files }
    described_class.new(current.merge(measured))
  end
  let(:specs) { ->(file) { file.end_with?("_spec.rb") } }

  def mismatch(own = described_class::NONE, **over)
    stored.mismatches(current.merge(over.transform_keys(&:to_s)), own).first
  end

  it "matches the fingerprint it was stored with" do
    expect(stored.mismatches(current)).to(eq([]))
  end

  it "does not match another format" do
    expect(described_class.new(current).mismatches(current)).to(eq(["it was stored by another kimera version"]))
  end

  it "does not match another Ruby, naming both" do
    expect(mismatch(ruby: "ruby 3.4.8")).to(eq("it was measured on ruby 4.0.7, not ruby 3.4.8"))
  end

  it "does not match other settings" do
    expect(mismatch(settings: "s2")).to(eq("the settings that pick the tests and sources changed"))
  end

  it "names the first test, support or config file that changed, was added or is gone" do
    changed = [
      { ".rspec" => "x", "spec/a_spec.rb" => "a", "spec/b_spec.rb" => "b" },
      current["files"].merge("spec/c_spec.rb" => "c")
    ]
    expect(changed.map { |files| mismatch(files: files) } << mismatch(files: { ".rspec" => "r" }))
      .to(eq([".rspec changed", "spec/c_spec.rb changed", "spec/a_spec.rb changed"]))
  end

  it "still matches when only the test files it is told own their tests changed, and names a support file" do
    edited = current["files"].merge("spec/a_spec.rb" => "x", "spec/support.rb" => "s")
    expect([mismatch(specs, files: edited), mismatch(specs, files: current["files"].merge("spec/a_spec.rb" => "x"))])
      .to(eq(["spec/support.rb changed", nil]))
  end

  def reused(sources, files = [], ids = %w[t1 t2 t3 t4])
    now = current.merge("sources" => sources)
    picked = stored.picked(now, files, ids)
    [picked, stored.reused(now, picked.size, ids.size)]
  end

  def reusing = "kimera: reusing the coverage map from 0123456"

  it "picks the tests of the sources that changed since, were added or are gone" do
    notice = "#{reusing} (2 source and 0 test file(s) changed since): the baseline runs 1 of 4 tests"
    expect(reused("lib/a.rb" => "1", "lib/b.rb" => "9", "lib/c.rb" => "3")).to(eq([%w[t3], notice]))
  end

  it "counts a source that is gone as changed" do
    expect(reused("lib/a.rb" => "1").last).to(include("(1 source and 0 test file(s) changed since)"))
  end

  it "picks the tests that reached the given files, and the tests it never saw, in the suite's order" do
    expect(stored.picked(current, %w[lib/b.rb lib/z.rb], %w[t5 t1 t3 t4])).to(eq(%w[t5 t3]))
  end

  it "picks every test an edited test file holds, and only those, counting the file" do
    now = current.merge("files" => current["files"].merge("spec/b_spec.rb" => "x"))
    picked = stored.picked(now, [], %w[t1 t2 t3 t4], specs)
    expect([picked, stored.reused(now, picked.size, 4, specs)])
      .to(eq([%w[t3 t4], "#{reusing} (0 source and 1 test file(s) changed since): the baseline runs 2 of 4 tests"]))
  end

  it "names no commit when it was stored outside git" do
    map = described_class.new(current.merge("commit" => nil, "sources" => {}, "coverage" => {}, "tests" => []))
    expect(map.reused(current.merge("sources" => {}), 0, 0)).to(start_with("kimera: reusing the coverage map from  (0"))
  end

  it "reads back what it wrote, creating the folder and naming its format" do
    Dir.mktmpdir("kimera-map") do |dir|
      path = File.join(dir, "tmp", "kimera", "coverage.json")
      described_class.new(current.merge("coverage" => {}, "tests" => [])).write(path)
      expect(described_class.read(path).mismatches(current)).to(eq([]))
    end
  end
end
