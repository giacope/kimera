# frozen_string_literal: true

require "kimera/cli/run"
require "kimera/registry/builder"
require "tmpdir"

RSpec.describe(Kimera::CLI::Run::Route) do
  let(:registry) { Kimera::RegistryScan.new.source("def m(a, b)\n  a > b\nend\n", file: "app/x.rb") }
  let(:ids) { registry.each.map { |mutant, _point| mutant.to_i } }

  it "isolates the mutants a pool-unsafe test covers, reading coverage only for a pattern", :aggregate_failures do
    reads = 0
    coverage = -> { (reads += 1) && { ids.first => ["spec/acp/end_to_end_spec.rb[1:1]"] } }
    apart, together = described_class.new(registry, isolate_when_covered_by: ["end_to_end_spec"]).split(ids, &coverage)
    expect([apart, together, reads]).to(eq([[ids.first], ids.drop(1), ids.size]))
  end

  it "reads no coverage without a pattern" do
    expect { described_class.new(registry, {}).split(ids) { raise(ArgumentError, "coverage read without a pattern") } }
      .not_to(raise_error)
  end

  def own(path, root)
    scanned = Kimera::RegistryScan.new(root: root, shielded: false).build([path])
    described_class.new(scanned, source_root: root).split(scanned.each.map { |mutant, _point| mutant.to_i }) { {} }
  end

  it "judges kimera's own runtime and child entrypoints apart, where the warm pool cannot weave them" do
    lib = File.expand_path("../../../../lib", __dir__)
    paths = [Kimera::Runtime::SOURCE_PATH, *Kimera::SelfProtection::OUT_OF_PROCESS_ENTRYPOINTS]
    expect(paths.map { |path| own(path, lib) }).to(all(match([be_any, be_empty])))
  end

  it "keeps a project's own runtime.rb in the warm pool" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "runtime.rb"), "def m(a, b)\n  a > b\nend\n")
      expect(own(File.join(dir, "runtime.rb"), dir)).to(match([be_empty, be_any]))
    end
  end

  it "judges isolated-only mutants on incremental runs unless told otherwise", :aggregate_failures do
    expect(described_class.new(registry, since: "origin/main").judging?).to(be(true))
    expect(described_class.new(registry, {}).judging?).to(be(false))
    expect(described_class.new(registry, since: "origin/main", judge_isolated_only: false).judging?).to(be(false))
    expect(described_class.new(registry, judge_isolated_only: true).judging?).to(be(true))
  end

  it "confirms survivors on every run unless told otherwise", :aggregate_failures do
    expect(described_class.new(registry, since: "origin/main").confirming?).to(be(true))
    expect(described_class.new(registry, {}).confirming?).to(be(true))
    expect(described_class.new(registry, confirm_survivors: nil).confirming?).to(be(true))
    expect(described_class.new(registry, since: "origin/main", confirm_survivors: false).confirming?).to(be(false))
    expect(described_class.new(registry, confirm_survivors: false).confirming?).to(be(false))
  end
end
