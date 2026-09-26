# frozen_string_literal: true

require "kimera/incremental/session"
require "kimera/registry/builder"
require "tmpdir"

RSpec.describe(Kimera::Incremental::Session) do
  let(:dir) { Dir.mktmpdir }

  after { FileUtils.remove_entry(dir) }

  def result(id, status)
    Kimera::MutantResult.new(mutant_id: id, status: status, file: "x.rb", duration: 0.1)
  end

  def report(results, leaks = [])
    Kimera::RunReport.new(results: results, leaks: leaks)
  end

  def seed(dir, report, registry: nil, meta: {})
    path = File.join(dir, "session.json")
    described_class.new.tap { |s| s.merge!(report) }.save(path, registry: registry, meta: meta)
    path
  end

  it "records, persists, and resumes results" do
    path = seed(dir, report([result(1, :killed), result(2, :survived)]))
    resumed = described_class.load(path)
    actual = [resumed.results.keys.sort, resumed.done?(1), resumed.done?(3), resumed.results[2].status]
    expect(actual).to(eq([[1, 2], true, false, :survived]))
  end

  it "preserves loaded meta when the session is saved again" do
    path = seed(dir, report([result(1, :killed)]), meta: { "since" => "main" })
    described_class.load(path).save(path)
    expect(JSON.parse(File.read(path))["meta"]).to(eq("since" => "main"))
  end

  it "merges new results into resumed ones" do
    path = seed(dir, report([result(1, :killed)]))
    resumed = described_class.load(path)
    resumed.merge!(report([result(2, :killed)]))
    actual = [resumed.results.keys.sort, resumed.results.values.count(&:killed?)]
    expect(actual).to(eq([[1, 2], 2]))
  end

  describe "staleness invalidation on resume" do
    # Mutant ids are positional, so an edit can point a stored id at a
    # different mutation.
    def registry(source)
      Kimera::RegistryScan.new.source(source, file: "calc.rb")
    end

    def first(registry)
      registry.each.first.first.id
    end

    it "reuses results when the source (and thus fingerprint) is unchanged" do
      registry = registry("def m(a, b)\n  a > b\nend\n")
      id = first(registry)
      path = seed(dir, report([result(id, :killed)]), registry: registry)
      resumed = described_class.load(path, registry: registry)
      expect(resumed.done?(id)).to(be(true))
    end

    it "drops a stored result whose mutation at that id changed" do
      origin = registry("def m(a, b)\n  a > b\nend\n")
      id = first(origin)
      path = seed(dir, report([result(id, :killed)]), registry: origin)
      resumed = described_class.load(path, registry: registry("def m(a, b)\n  a < b\nend\n"))
      expect(resumed.done?(id)).to(be(false))
    end

    it "drops leaks whose result was dropped as stale" do
      id = first(registry("def m(a, b)\n  a > b\nend\n"))
      leak = Kimera::LeakReport.new(mutant_id: id, detail: "leaked")
      path = seed(dir, report([result(id, :killed)], [leak]), registry: registry("def m(a, b)\n  a > b\nend\n"))
      resumed = described_class.load(path, registry: registry("def m(a, b)\n  a < b\nend\n"))
      expect([resumed.done?(id), resumed.leaks]).to(eq([false, []]))
    end

    it "records no fingerprint for a result whose id is not in the registry" do
      registry = registry("def m(a, b)\n  a > b\nend\n")
      path = seed(dir, report([result(999_999, :killed)]), registry: registry)
      expect(JSON.parse(File.read(path))["fingerprints"]).to(eq({}))
    end

    it "drops unfingerprinted (legacy) entries when a registry is supplied" do
      registry = registry("def m(a, b)\n  a > b\nend\n")
      id = first(registry)
      path = seed(dir, report([result(id, :killed)]))
      matched = described_class.load(path, registry: registry).done?(id)
      expect([matched, described_class.load(path).done?(id)]).to(eq([false, true]))
    end
  end

  it "preserves leaks across persistence" do
    leak = Kimera::LeakReport.new(mutant_id: 5, detail: "leaked")
    path = seed(dir, report([result(1, :killed)], [leak]))
    expect(described_class.load(path).leaks.first.mutant_id).to(eq(5))
  end
end
