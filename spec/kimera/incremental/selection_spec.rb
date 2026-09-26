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
    ids = described_class.select(registry, changed)

    points = ids.map { |id| registry.index[id] }.uniq
    expect(points.map(&:original_source).uniq).to(eq(["x > y"]))
  end

  it "returns nothing when changes miss every mutation point" do
    changed = { "calc.rb" => Set[1, 4] } # class line + blank line
    expect(described_class.select(registry, changed)).to(be_empty)
  end

  it "selects all mutants on a multi-mutation changed line" do
    changed = { "calc.rb" => Set[7] } # `x < y && y > 0`
    ids = described_class.select(registry, changed)
    sources = ids.map { |id| registry.index[id].original_source }.uniq
    expect(sources).to(contain_exactly("x < y && y > 0", "x < y", "y > 0"))
  end

  it "ignores files not in the changed set" do
    changed = { "other.rb" => Set[3] }
    expect(described_class.select(registry, changed)).to(be_empty)
  end
end
