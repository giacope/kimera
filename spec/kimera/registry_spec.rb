# frozen_string_literal: true

require "kimera/registry/builder"
require "kimera/registry/registry"
require "tmpdir"

RSpec.describe(Kimera::Registry) do
  let(:registry) do
    Kimera::RegistryScan.new.source(<<~RUBY, file: "calc.rb")
      class Calc
        def a(x, y)
          x > y
        end
      end
    RUBY
  end

  def document(registry) = JSON.parse(registry.to_json)

  describe "construction and printing" do
    it "starts empty with defaults", :aggregate_failures do
      empty = described_class.new
      expect([empty.to_a, empty.to_h, empty.each.count]).to(eq([[], {}, 0]))
      expect(document(empty)).to(include("root" => ".", "operators" => [], "points" => [], "unmutated" => []))
    end

    it "groups its points by file", :aggregate_failures do
      expect(registry.to_h.keys).to(eq(["calc.rb"]))
      expect(registry.to_h.fetch("calc.rb")).to(eq(registry.to_a))
    end

    it "hands out a copy of its points" do
      registry.to_a.clear
      expect(registry.to_a.size).to(eq(1))
    end

    it "says how many mutants, points and files it found" do
      expect(registry.to_s).to(eq("Found #{registry.each.count} mutants at 1 mutation points across 1 files."))
    end
  end

  describe "#[] and #index" do
    it "looks up a mutant and its hosting point by id", :aggregate_failures do
      mutant, point = registry.each.first
      expect(registry[mutant.to_i]).to(eq([mutant, point]))
      expect(registry.index[mutant.to_i]).to(eq(point))
    end

    it "fails on an unknown mutant id, or answers what the block gives", :aggregate_failures do
      expect { registry[99_999] }.to(raise_error(KeyError))
      expect(registry[99_999] { :none }).to(eq(:none))
      expect(registry.index[99_999]).to(be_nil)
    end

    it "memoizes the lookup tables" do
      first = registry.index
      second = registry.index
      expect(first).to(be(second))
    end
  end

  describe "#each" do
    it "returns an Enumerator without a block", :aggregate_failures do
      enum = registry.each
      expect(enum).to(be_a(Enumerator))
      expect(enum.map { |m, _p| m.to_i }).to(eq(registry.each.map { |m, _p| m.to_i }))
    end
  end

  describe "#texts" do
    def rooted(dir)
      path = File.join(dir, "kinds.rb").tap { File.write(it, "def kinds = %i[fast slow].size\n") }
      Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: %w[symbol_literal]), root: dir).build([path])
    end

    it "renders a mutant against the source under its root" do
      Dir.mktmpdir do |dir|
        registry = rooted(dir)
        texts = registry.each.map { |mutant, point| registry.texts(point, mutant, Kimera::Rewrite::MutantText) }
        expect(texts).to(eq([[":fast__kimera__"], [":slow__kimera__"]]))
      end
    end
  end

  describe "#regions and #narrowed" do
    let(:regions) do
      [Kimera::Unmutated.block("a.rb", 2, 3), Kimera::Unmutated.block("b.rb", 7, 7)]
    end

    it "hands its unmutated regions to the block" do
      rows = described_class.new(unmutated: regions).regions { it.map(&:to_h) }
      expect(rows.map { |row| row.values_at("file", "start_line") }).to(eq([["a.rb", 2], ["b.rb", 7]]))
    end

    it "keeps only the regions a change touches, and every point", :aggregate_failures do
      narrowed = described_class.new(points: registry.to_a, unmutated: regions).narrowed("b.rb" => [7])
      expect(narrowed.regions(&:itself).map(&:place)).to(eq(["b.rb:7"]))
      expect(narrowed.to_a).to(eq(registry.to_a))
    end
  end

  describe "serialization" do
    it "prints its format version and stats as JSON", :aggregate_failures do
      h = document(registry)
      expect(h["format_version"]).to(eq(described_class::FORMAT_VERSION))
      expect(h["stats"]).to(eq("files" => 1, "points" => 1, "mutants" => registry.each.count))
    end

    it "prints the same JSON pretty or plain" do
      expect(JSON.parse(JSON.pretty_generate(registry))).to(eq(document(registry)))
    end

    it "round-trips to and from a file via from_file", :aggregate_failures do
      Dir.mktmpdir do |dir|
        reloaded = described_class.from_file(File.join(dir, "r.json").tap { File.write(it, JSON.generate(registry)) })
        expect(reloaded.each.count).to(eq(registry.each.count))
        expect(reloaded.to_a.first.original_source).to(eq(registry.to_a.first.original_source))
      end
    end

    it "defaults root/operators/points when absent from a hash" do
      expect(document(described_class.from_h({}))).to(include("root" => ".", "operators" => [], "points" => []))
    end
  end
end
