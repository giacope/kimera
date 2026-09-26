# frozen_string_literal: true

require "kimera/registry/builder"
require "kimera/scope/ignore_list"

RSpec.describe(Kimera::IgnoreList) do
  let(:source) do
    <<~RUBY
      class Calc
        def a(x, y)
          x > y
        end

        def b(x, y)
          x < y
        end
      end
    RUBY
  end

  let(:registry) { Kimera::RegistryScan.new.source(source, file: "calc.rb") }

  let(:first_column) do
    all = ids(file: "calc.rb", line: 3)
    registry.index[all.first].location.start_column
  end

  def ids(rule)
    described_class.ids(registry, [rule])
  end

  it "matches by file + line + label" do
    ids = ids(file: "calc.rb", line: 3, label: "> => <")
    labels = ids.map { |id| registry.mutant(id).label }
    expect(labels).to(eq(["> => <"]))
  end

  it "matches all mutants on a line when only file + line given" do
    ids = ids(file: "calc.rb", line: 3)
    expect(ids.size).to(eq(2)) # both > variants
  end

  it "supports glob file patterns" do
    expect(ids(file: "**/*.rb", line: 7)).not_to(be_empty)
  end

  it "matches by enclosing method name, independent of line position", :aggregate_failures do
    ids = ids(file: "calc.rb", method: "b", label: "< => >")
    labels = ids.map { |id| registry.mutant(id).label }
    expect(labels).to(eq(["< => >"]))
    expect(ids(file: "calc.rb", method: "a", label: "< => >")).to(be_empty)
  end

  it "matches by original snippet" do
    ids = ids(file: "calc.rb", original: "x < y")
    sources = ids.map { |id| registry.index[id].original_source }.uniq
    expect(sources).to(eq(["x < y"]))
  end

  it "matches an original snippet across a re-indent or line wrap" do
    ids = ids(file: "calc.rb", original: "x\n  <   y")
    sources = ids.map { |id| registry.index[id].original_source }.uniq
    expect(sources).to(eq(["x < y"]))
  end

  it "still distinguishes snippets that differ in tokens, not layout" do
    expect(ids(file: "calc.rb", original: "x <= y")).to(be_empty)
  end

  it "returns nothing for a non-matching rule", :aggregate_failures do
    expect(ids(file: "calc.rb", line: 999)).to(be_empty)
    expect(described_class.ids(registry, [])).to(be_empty)
  end

  it "matches nothing for a rule that omits the file field", :aggregate_failures do
    expect(ids(line: 3)).to(be_empty)
    expect(ids(label: "> => <")).to(be_empty)
  end

  it "matches nothing when the file glob matches no point" do
    expect(ids(file: "other/**/*.rb", line: 3)).to(be_empty)
  end

  it "requires the label to match exactly when given" do
    expect(ids(file: "calc.rb", line: 3, label: "no such label")).to(be_empty)
  end

  it "pins a single point by column when a line has several matches", :aggregate_failures do
    pinned = ids(file: "calc.rb", line: 3, column: first_column)
    expect(pinned).not_to(be_empty)
    expect(pinned.map { |id| registry.index[id].location.start_column }.uniq).to(eq([first_column]))
  end

  it "matches nothing when the column does not match any point on the line" do
    expect(ids(file: "calc.rb", line: 3, column: 999)).to(be_empty)
  end

  describe ".stale" do
    it "flags a rule whose file is in the registry but whose anchor drifted" do
      drifted = { file: "calc.rb", line: 999, label: "> => <" }
      expect(described_class.stale(registry, [drifted])).to(eq([drifted]))
    end

    it "does not flag a matching rule" do
      live = { file: "calc.rb", line: 3, label: "> => <" }
      expect(described_class.stale(registry, [live])).to(be_empty)
    end

    it "does not flag a rule for a file outside this run's scope" do
      ignored = { file: "other/thing.rb", line: 3 }
      expect(described_class.stale(registry, [ignored])).to(be_empty)
    end

    it "ignores rules without a file field" do
      expect(described_class.stale(registry, [{ line: 3 }])).to(be_empty)
    end
  end
end
