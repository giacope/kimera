# frozen_string_literal: true

require "kimera/incremental/coverage_map"
require "tmpdir"

RSpec.describe(Kimera::Incremental::CoverageMap) do
  let(:current) do
    { "commit" => "0123456789abcdef", "ruby" => "ruby 4.0.7", "settings" => "s1" }
      .merge("files" => { "spec/a_spec.rb" => "a", ".rspec" => "r" })
      .merge("sources" => { "lib/a.rb" => "1", "lib/b.rb" => "2" })
  end
  let(:stored) do
    coverage = { "lib/a.rb" => %w[t1 t2], "lib/b.rb" => %w[t3] }
    described_class.new(current.merge("format" => 1, "coverage" => coverage, "tests" => %w[t1 t2 t3 t4]))
  end

  def mismatch(**over) = stored.mismatch(current.merge(over.transform_keys(&:to_s)))

  it "matches the fingerprint it was stored with" do
    expect(stored.mismatch(current)).to(be_nil)
  end

  it "does not match another format" do
    expect(described_class.new(current).mismatch(current)).to(eq("it was stored by another kimera version"))
  end

  it "does not match another Ruby, naming both" do
    expect(mismatch(ruby: "ruby 3.4.8")).to(eq("it was measured on ruby 4.0.7, not ruby 3.4.8"))
  end

  it "does not match other settings" do
    expect(mismatch(settings: "s2")).to(eq("the settings that pick the tests and sources changed"))
  end

  it "names the first test, support or config file that changed, was added or is gone" do
    changed = [
      { ".rspec" => "x", "spec/a_spec.rb" => "a" },
      { ".rspec" => "r", "spec/a_spec.rb" => "a", "spec/b_spec.rb" => "b" }
    ]
    expect(changed.map { |files| mismatch(files: files) } << mismatch(files: { ".rspec" => "r" }))
      .to(eq([".rspec changed", "spec/b_spec.rb changed", "spec/a_spec.rb changed"]))
  end

  it "lists the sources that changed since, were added or are gone" do
    expect(stored.changed("lib/a.rb" => "1", "lib/b.rb" => "9", "lib/c.rb" => "3")).to(eq(%w[lib/b.rb lib/c.rb]))
  end

  it "lists a source that is gone" do
    expect(stored.changed("lib/a.rb" => "1")).to(eq(%w[lib/b.rb]))
  end

  it "picks the tests that reached the given files, and the tests it never saw, in the suite's order" do
    expect(stored.tests(%w[lib/b.rb lib/z.rb], %w[t5 t1 t3 t4])).to(eq(%w[t5 t3]))
  end

  it "names its commit short" do
    expect(stored.commit).to(eq("0123456"))
  end

  it "names no commit when it was stored outside git" do
    expect(described_class.new({}).commit).to(eq(""))
  end

  it "reads back what it wrote, creating the folder and naming its format" do
    Dir.mktmpdir("kimera-map") do |dir|
      path = File.join(dir, "tmp", "kimera", "coverage.json")
      described_class.new(current.merge("coverage" => {}, "tests" => [])).write(path)
      expect(described_class.read(path).mismatch(current)).to(be_nil)
    end
  end
end
