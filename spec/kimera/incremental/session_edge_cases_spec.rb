# frozen_string_literal: true

require "kimera/incremental/session"
require "kimera/registry/registry"
require "tmpdir"

RSpec.describe(Kimera::Incremental::Session) do
  def stored(session) = session.report([1, 2, 3], [], Kimera::Registry.new).results

  it "loads a fresh empty session when the path is nil or missing", :aggregate_failures do
    expect(stored(described_class.from(nil))).to(eq([]))
    Dir.mktmpdir { |dir| expect(stored(described_class.from(File.join(dir, "absent.json")))).to(eq([])) }
  end

  it "tolerates a file with no results or leaks keys" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "s.json").tap { |p| File.write(p, JSON.generate("version" => 1, "meta" => {})) }
      report = described_class.from(path).report([1], [], Kimera::Registry.new)
      expect([report.results, report.leaks]).to(eq([[], []]))
    end
  end

  it "accepts seeded results and leaks via the constructor" do
    result = Kimera::MutantResult.new(mutant_id: 1, status: :killed, file: "x.rb", duration: 0.0)
    leak = Kimera::LeakReport.new(mutant_id: 2, detail: "leak")
    report = described_class.new(results: { 1 => result }, leaks: [leak]).report([1], [], Kimera::Registry.new)
    expect([report.results.map(&:killed?), report.leaks]).to(eq([[true], [leak]]))
  end

  def resaved(path, registry = Kimera::Registry.new)
    described_class.new.save(path, registry, meta: { "since" => "main" })
    described_class.from(path).save(path, registry, meta: { "extra" => "v" })
    JSON.parse(File.read(path))["meta"]
  end

  it "merges the meta it saves into the meta it resumed" do
    Dir.mktmpdir { |dir| expect(resaved(File.join(dir, "s.json"))).to(eq("since" => "main", "extra" => "v")) }
  end
end
