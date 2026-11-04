# frozen_string_literal: true

require "kimera/incremental/selection"
require "kimera/registry/builder"

RSpec.describe(Kimera::Incremental::Selection) do
  let(:source) do
    <<~RUBY
      class Calc
        def a(x, y)
          x > y
        end

        def b(x, y)
          x < y && y > 0
        end
      end
    RUBY
  end

  let(:registry) { Kimera::RegistryScan.new.source(source, file: "calc.rb") }

  it "selects only mutants whose point overlaps a changed line" do
    changed = { "calc.rb" => Set[3] } # the `x > y` line
    ids = described_class.new(changed, "main").ids(registry)

    points = ids.map { |id| registry.index[id] }.uniq
    expect(points.map(&:original_source).uniq).to(eq(["x > y"]))
  end

  it "returns nothing when changes miss every mutation point" do
    changed = { "calc.rb" => Set[1, 4] } # class line + blank line
    expect(described_class.new(changed, "main").ids(registry)).to(be_empty)
  end

  it "selects all mutants on a multi-mutation changed line" do
    changed = { "calc.rb" => Set[7] } # `x < y && y > 0`
    ids = described_class.new(changed, "main").ids(registry)
    sources = ids.map { |id| registry.index[id].original_source }.uniq
    expect(sources).to(contain_exactly("x < y && y > 0", "x < y", "y > 0"))
  end

  it "ignores files not in the changed set" do
    changed = { "other.rb" => Set[3] }
    expect(described_class.new(changed, "main").ids(registry)).to(be_empty)
  end

  it "keeps the changed files, named as the block relates them" do
    selection = described_class.new({ "calc.rb" => Set[3] }, "main")
    expect(selection.files(["/p/calc.rb", "/p/other.rb"]) { |file| File.basename(file) }).to(eq(["/p/calc.rb"]))
  end

  it "announces how many mutants the change selects, and since when" do
    io = StringIO.new
    described_class.new({}, "v1.2").announce(io, [4, 5, 6], 2)
    expect(io.string).to(eq("Incremental: 3 mutants on lines changed since v1.2 (2 changed files).\n"))
  end
end
