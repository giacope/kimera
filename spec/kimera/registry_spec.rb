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

  describe "construction and accessors" do
    it "starts empty with defaults" do
      expect(described_class.new).to(have_attributes(size: 0, count: 0, files: [], root: ".", operators: []))
    end

    it "appends points via << and returns self", :aggregate_failures do
      registry = described_class.new
      point = registry.points.first
      expect(registry << point).to(be(registry))
      expect(registry.size).to(eq(1))
    end

    it "lists unique files and points at a file", :aggregate_failures do
      expect(registry.files).to(eq(["calc.rb"]))
      expect(registry.at("calc.rb")).to(eq(registry.points))
      expect(registry.at("other.rb")).to(eq([]))
    end
  end

  describe "#mutant and #index" do
    it "looks up a mutant and its hosting point by id", :aggregate_failures do
      mutant, point = registry.each.first
      expect(registry.mutant(mutant.id)).to(eq(mutant))
      expect(registry.index[mutant.id]).to(eq(point))
    end

    it "returns nil for an unknown mutant id", :aggregate_failures do
      expect(registry.mutant(99_999)).to(be_nil)
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
      expect(enum.map { |m, _p| m.id }).to(eq(registry.each.map { |m, _p| m.id }))
    end
  end

  describe "serialization" do
    it "exposes format version and stats in to_h", :aggregate_failures do
      h = registry.to_h
      expect(h["format_version"]).to(eq(described_class::FORMAT_VERSION))
      expect(h["stats"]).to(eq("files" => 1, "points" => registry.size, "mutants" => registry.count))
    end

    def written(path)
      expect(registry.write(path)).to(eq(path))
      described_class.from_file(path)
    end

    it "round-trips to and from a file via write/from_file", :aggregate_failures do
      Dir.mktmpdir do |dir|
        reloaded = written(File.join(dir, "registry.json"))
        expect(reloaded.count).to(eq(registry.count))
        expect(reloaded.points.first.original_source).to(eq(registry.points.first.original_source))
      end
    end

    it "defaults root/operators/points when absent from a hash", :aggregate_failures do
      registry = described_class.from_h({})
      expect(registry.root).to(eq("."))
      expect(registry.operators).to(eq([]))
      expect(registry.points).to(eq([]))
    end
  end
end
