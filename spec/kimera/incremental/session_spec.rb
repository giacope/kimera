# frozen_string_literal: true

require "kimera/incremental/session"
require "kimera/registry/builder"
require "tmpdir"

using ResultFields

RSpec.describe(Kimera::Incremental::Session) do
  let(:dir) { Dir.mktmpdir }

  after { FileUtils.remove_entry(dir) }

  def result(id, status)
    Kimera::MutantResult.new(mutant_id: id, status: status, file: "x.rb", duration: 0.1)
  end

  def report(results, leaks = [])
    Kimera::RunReport.new(results: results, leaks: leaks)
  end

  # A session that judged the report's mutants with it.
  def judged(report, session = described_class.new) = session.judged(report.to_a.map(&:mutant_id)) { report }

  def seed(dir, report, registry: Kimera::Registry.new, meta: {})
    path = File.join(dir, "session.json")
    judged(report).save(path, registry, meta: meta)
    path
  end

  # The stored results of +ids+ a session reports, in order, and the ids it still has to judge.
  def stored(session, ids = [1, 2, 3]) = session.report(ids, [], Kimera::Registry.new).to_a

  def pending(session, ids)
    [].tap { |left| session.judged(ids) { |remaining| left.concat(remaining).then { report([]) } } }
  end

  def done?(session, id) = pending(session, [id]).empty?

  def leaks(session) = session.report([], [], Kimera::Registry.new).notes.to_h["leaks"]

  def stamped(stamp) = described_class.new(meta: { "stamp" => stamp })

  it "keeps each mutant's killing tests and the suite a test-quality run saw across a save", :aggregate_failures do
    counted = result(1, :killed).with(killing_tests: %w[t1 t2])
    path = seed(dir, report([counted]).annotate(suite: %w[t1 t2 t3]))
    resumed = described_class.from(path).report([1], [], Kimera::Registry.new)
    expect([resumed.to_a.first.killing_tests, resumed.notes.to_h["suite"]]).to(eq([%w[t1 t2], %w[t1 t2 t3]]))
  end

  it "keeps the flaky tests a run found across a save and a resume", :aggregate_failures do
    found = { "runs" => 1, "seeds" => [2], "tests" => 1, "flaky" => [] }
    path = seed(dir, report([result(1, :killed)]).annotate(flaky: found))
    expect(described_class.from(path).report([1], [], Kimera::Registry.new).notes.to_h["flaky"]).to(eq(found))
    expect(judged(report([])).report([], [], Kimera::Registry.new).notes.to_h["flaky"]).to(be_nil)
  end

  it "creates the directory it saves into" do
    path = File.join(dir, "tmp", "kimera", "session.json")
    described_class.new.save(path, Kimera::Registry.new)
    expect(File).to(exist(path))
  end

  it "answers itself once it has saved" do
    session = described_class.new
    expect(session.save(File.join(dir, "session.json"), Kimera::Registry.new)).to(be(session))
  end

  # The tests or sources changed since: a kill may no longer stand.
  it "drops verdicts saved under another stamp, and keeps those saved under the same", :aggregate_failures do
    registry = Kimera::RegistryScan.new.source("def a(x, y)\n  x > y\nend\n", file: "x.rb")
    id = registry.each.first.first.id
    path = File.join(dir, "session.json")
    judged(report([result(id, :killed)]), stamped("one")).save(path, registry)
    expect(%w[two one].map { |stamp| done?(described_class.from(path, stamp: stamp).pruned(registry), id) })
      .to(eq([false, true]))
  end

  # A run starts its session from no file under the run's stamp; saved, the stamp lets the next run resume it.
  it "stamps the session a run starts, so the next run under the same stamp keeps its verdicts" do
    registry = Kimera::RegistryScan.new.source("def a(x, y)\n  x > y\nend\n", file: "x.rb")
    id = registry.each.first.first.id
    path = File.join(dir, "session.json")
    judged(report([result(id, :killed)]), described_class.from(path, stamp: "one")).save(path, registry)
    expect(done?(described_class.from(path, stamp: "one").pruned(registry), id)).to(be(true))
  end

  it "drops leaks saved under another stamp with the verdicts they explain", :aggregate_failures do
    path = File.join(dir, "session.json")
    leak = Kimera::LeakReport.new(mutant_id: 1, detail: "leaked")
    judged(report([result(1, :killed)], [leak]), stamped("one")).save(path, Kimera::Registry.new)
    expect(leaks(described_class.from(path, stamp: "two"))).to(eq([]))
    expect(leaks(described_class.from(path, stamp: "one")).map(&:mutant_id)).to(eq([1]))
  end

  it "records, persists, and resumes results" do
    path = seed(dir, report([result(1, :killed), result(2, :survived)]))
    resumed = described_class.from(path)
    actual = [stored(resumed).map(&:mutant_id), done?(resumed, 1), done?(resumed, 3), stored(resumed, [2]).first.status]
    expect(actual).to(eq([[1, 2], true, false, :survived]))
  end

  it "preserves loaded meta when the session is saved again" do
    path = seed(dir, report([result(1, :killed)]), meta: { "since" => "main" })
    described_class.from(path).save(path, Kimera::Registry.new)
    expect(JSON.parse(File.read(path))["meta"]).to(eq("since" => "main"))
  end

  it "keeps the names of the tests its results cite across a resume" do
    named = { "t1" => { "name" => "N", "location" => "spec/n_spec.rb:2" } }
    path = seed(dir, Kimera::RunReport.new(results: [result(1, :killed)], tests: named))
    expect(described_class.from(path).report([1], [], Kimera::Registry.new).notes.to_h["tests"]).to(eq(named))
  end

  it "merges new results into resumed ones" do
    path = seed(dir, report([result(1, :killed)]))
    resumed = judged(report([result(2, :killed)]), described_class.from(path))
    actual = [stored(resumed).map(&:mutant_id), stored(resumed).count(&:killed?)]
    expect(actual).to(eq([[1, 2], 2]))
  end

  describe "ignored mutants" do
    let(:registry) { Kimera::RegistryScan.new.source("def m(a, b)\n  a > b\nend\n", file: "calc.rb") }

    def ids = registry.each.map { |mutant, _point| mutant.id }

    def waived(session) = session.report([], ids, registry).to_a

    it "reports an evaluated ignored mutant as ignored with its stored verdict", :aggregate_failures do
      first, second = ids
      path = seed(dir, report([result(first, :killed)]), registry: registry)
      rows = waived(described_class.from(path).pruned(registry))
      expect(rows.map { |row| [row.status, row.verdict, row.detail, row.file] }).to(
        eq([[:ignored, :killed, "ignored (killed)", "x.rb"], [:ignored, nil, "marked equivalent (ignored)", "calc.rb"]])
      )
      expect(rows.last.mutant_id).to(eq(second))
    end
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
      resumed = described_class.from(path).pruned(registry)
      expect(done?(resumed, id)).to(be(true))
    end

    it "drops a stored result whose mutation at that id changed" do
      origin = registry("def m(a, b)\n  a > b\nend\n")
      id = first(origin)
      path = seed(dir, report([result(id, :killed)]), registry: origin)
      resumed = described_class.from(path).pruned(registry("def m(a, b)\n  a < b\nend\n"))
      expect(done?(resumed, id)).to(be(false))
    end

    it "drops a stored result whose id the registry no longer has" do
      origin = registry("def m(a, b)\n  a > b\nend\n")
      id = first(origin)
      path = seed(dir, report([result(id, :killed)]), registry: origin)
      expect(done?(described_class.from(path).pruned(Kimera::Registry.new), id)).to(be(false))
    end

    it "drops leaks whose result was dropped as stale" do
      id = first(registry("def m(a, b)\n  a > b\nend\n"))
      leak = Kimera::LeakReport.new(mutant_id: id, detail: "leaked")
      path = seed(dir, report([result(id, :killed)], [leak]), registry: registry("def m(a, b)\n  a > b\nend\n"))
      resumed = described_class.from(path).pruned(registry("def m(a, b)\n  a < b\nend\n"))
      expect([done?(resumed, id), leaks(resumed)]).to(eq([false, []]))
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
      matched = done?(described_class.from(path).pruned(registry), id)
      expect([matched, done?(described_class.from(path), id)]).to(eq([false, true]))
    end
  end

  it "preserves leaks across persistence" do
    leak = Kimera::LeakReport.new(mutant_id: 5, detail: "leaked")
    path = seed(dir, report([result(1, :killed)], [leak]))
    expect(leaks(described_class.from(path)).first.mutant_id).to(eq(5))
  end
end
