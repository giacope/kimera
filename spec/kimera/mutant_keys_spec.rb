# frozen_string_literal: true

require "kimera/registry/builder"

RSpec.describe(Kimera::MutantKeys, :aggregate_failures) do
  let(:sample) { File.expand_path("../../examples/sample_app", __dir__) }

  def scan(source, file: "a.rb") = Kimera::RegistryScan.new.source(source, file: file)

  def keys(registry) = registry.each.map { |mutant, _point| registry.keys[mutant.id] }

  def digests(registry) = keys(registry).map { |key| key[/\h{8}\z/] }

  def point(**changes)
    facts = { file: "a.rb", method_name: "a", operator: "comparison", original_source: "x > 1" }
    Kimera::MutationPoint.new(**facts, location: Kimera::Location.new(start_line: 2), **changes)
  end

  def key(changed = point, label: "> => >=")
    described_class::Fingerprint.new(changed, Kimera::Mutant.new(label: label)).key(Hash.new(0))
  end

  it "names a mutant the same whether its file was scanned alone or with others" do
    pricing = File.join(sample, "app/services/pricing.rb")
    alone = Kimera::RegistryScan.new(root: sample).build([pricing])
    full = Kimera::RegistryScan.new(root: sample).build(Dir[File.join(sample, "app/**/*.rb")])
    ids = full.at("app/services/pricing.rb").flat_map(&:ids)
    expect(ids.map { |id| full.keys[id] }).to(eq(keys(alone)))
    expect(ids.first).not_to(eq(alone.each.first.first.id))
  end

  it "keys by path, line, and a digest that ignores the line" do
    expect(key).to(match(/\Aa\.rb:2:\h{8}\z/))
    expect(key(point(location: Kimera::Location.new(start_line: 9)))).to(eq(key.sub(":2:", ":9:")))
    expect(key(point(original_source: "x  >\n  1"))).to(eq(key))
  end

  it "digests the file, method, operator, source, and label" do
    changed = [
      key(point(file: "b.rb")).sub("b.rb", "a.rb"), key(point(method_name: "b")),
      key(point(operator: "arithmetic")), key(point(original_source: "x > 2")), key(label: "> => <")
    ]
    expect(changed.uniq.size).to(eq(5))
    expect(changed).not_to(include(key))
  end

  it "keeps a mutant's digest when lines shift or an identical method is added above it" do
    method = "def b(x)\n  x > 1\nend\n"
    alone = scan(method)
    moved = scan("def a(x)\n  x > 1\nend\n\n#{method}")
    expect(digests(moved).last(alone.count)).to(eq(digests(alone)))
    expect(digests(moved).first(alone.count)).not_to(eq(digests(alone)))
    expect(keys(moved).last).to(start_with("a.rb:6:"))
  end

  it "tells identical mutants in one method apart" do
    twice = scan("def a(x)\n  x > 1 && x > 1\nend\n")
    comparisons = twice.each.select { |_mutant, spot| spot.original_source == "x > 1" }
    expect(comparisons.map { |mutant, _spot| twice.keys[mutant.id][/\h{8}\z/] }.uniq.size).to(eq(comparisons.size))
  end

  describe "#id" do
    let(:keys) { described_class.new(1 => "a.rb:2:0123abcd", 2 => "a.rb:9:fedcba98", 3 => "b.rb:2:0123abcd") }

    it "reads an ordinal as a decimal id" do
      expect([keys.id("2"), keys.id(2), keys.id("010")]).to(eq([2, 2, 10]))
    end

    it "resolves an exact key, then a key whose line moved" do
      expect(keys.id("a.rb:9:fedcba98")).to(eq(2))
      expect(keys.id("a.rb:40:fedcba98")).to(eq(2))
      expect(keys.id("b.rb:7:0123abcd")).to(eq(3))
    end

    it "returns a token it cannot resolve unchanged" do
      expect(keys.id("a.rb:2:ffffffff")).to(eq("a.rb:2:ffffffff"))
      expect(keys.id("c.rb:2:0123abcd")).to(eq("c.rb:2:0123abcd"))
      twin = described_class.new(1 => "a.rb:2:0123abcd", 2 => "a.rb:7:0123abcd")
      expect(twin.id("a.rb:5:0123abcd")).to(eq("a.rb:5:0123abcd"))
    end
  end
end
