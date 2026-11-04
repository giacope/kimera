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
    registry.index[all.first].location.to_h.fetch("start_column")
  end

  def ids(rule)
    described_class.new([rule]).resolve(registry).to_h[:ids]
  end

  it "matches by file + line + label" do
    ids = ids(file: "calc.rb", line: 3, label: "> => <")
    labels = ids.map { |id| registry[id].first.to_s }
    expect(labels).to(eq(["> => <"]))
  end

  it "matches all mutants on a line when only file + line given" do
    ids = ids(file: "calc.rb", line: 3)
    expect(ids.size).to(eq(2)) # both > variants
  end

  it "matches only points that start on the line given as starts:, not ones spanning it", :aggregate_failures do
    multi = Kimera::RegistryScan.new.source("def m(a)\n  if a\n    a > 1\n  end\nend\n", file: "m.rb")
    starting = described_class.new([{ file: "m.rb", starts: 3 }]).resolve(multi).to_h[:ids]
    spanning = described_class.new([{ file: "m.rb", line: 3 }]).resolve(multi).to_h[:ids]
    expect(starting.map { |id| multi.index[id].location.range.begin }.uniq).to(eq([3]))
    expect(spanning.size).to(be > starting.size)
  end

  it "matches by operator key, given as one key or several", :aggregate_failures do
    expect(ids(file: "calc.rb", operator: "comparison")).to(eq(ids(file: "calc.rb")))
    expect(ids(file: "calc.rb", operator: %w[arithmetic comparison])).to(eq(ids(file: "calc.rb")))
    expect(ids(file: "calc.rb", operator: ["conditional"])).to(be_empty)
  end

  it "supports glob file patterns" do
    expect(ids(file: "**/*.rb", line: 7)).not_to(be_empty)
  end

  it "matches by enclosing method name, independent of line position", :aggregate_failures do
    ids = ids(file: "calc.rb", method: "b", label: "< => >")
    labels = ids.map { |id| registry[id].first.to_s }
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
    expect(described_class.new([]).resolve(registry).to_h[:ids]).to(be_empty)
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
    pinned = ids(file: "calc.rb", line: 3, column: first_column + 1)
    expect(pinned).not_to(be_empty)
    expect(pinned.map { |id| registry.index[id].location.to_h.fetch("start_column") }.uniq).to(eq([first_column]))
  end

  # The report and the text report print 1-based columns; an entry copied
  # from either must match.
  it "reads the column 1-based, as the report prints it, not 0-based" do
    expect(ids(file: "calc.rb", line: 3, column: first_column)).to(be_empty)
  end

  it "matches nothing when the column does not match any point on the line" do
    expect(ids(file: "calc.rb", line: 3, column: 999)).to(be_empty)
  end

  describe "stale rules" do
    it "flags a rule whose file is in the registry but whose anchor drifted" do
      drifted = { file: "calc.rb", line: 999, label: "> => <", original: "x >= y" }
      expect(described_class.new([drifted]).resolve(registry).to_h[:stale]).to(eq([drifted]))
    end

    it "does not flag a matching rule" do
      live = { file: "calc.rb", line: 3, label: "> => <" }
      expect(described_class.new([live]).resolve(registry).to_h[:stale]).to(be_empty)
    end

    it "does not flag a rule for a file outside this run's scope" do
      ignored = { file: "lib/kimera.rb", line: 3 }
      expect(described_class.new([ignored]).resolve(registry).to_h[:stale]).to(be_empty)
    end

    it "flags a rule whose file no longer exists, which no scope can hold", :aggregate_failures do
      gone = { file: "lib/kimera/gone.rb", line: 3, label: "> => <" }
      expect(described_class.new([gone]).resolve(registry).to_h[:stale]).to(eq([gone]))
      expect(described_class.new([{ file: "lib/**/gone_*.rb", line: 3 }]).resolve(registry).to_h[:stale]).to(be_empty)
    end

    it "ignores rules without a file field" do
      expect(described_class.new([{ line: 3 }]).resolve(registry).to_h[:stale]).to(be_empty)
    end
  end

  describe ".resolve" do
    let(:source) do
      <<~RUBY
        class Calc
          def a(x, y)
            x > y
          end

          def b(x, y)
            x < y
          end

          def c(x, y)
            x < y
          end
        end
      RUBY
    end

    def resolve(*rules) = described_class.new(rules).resolve(registry)

    def labeled(label, line)
      registry.each.find { |mutant, point| mutant.to_s == label && point.location.range.begin == line }.first.to_i
    end

    it "re-anchors a drifted line when the label singles out one mutant", :aggregate_failures do
      rule = { file: "calc.rb", line: 2, label: "> => <" }
      resolution = resolve(rule)
      expect(resolution.to_h[:ids]).to(eq([labeled("> => <", 3)]))
      expect(resolution.to_h[:moved]).to(eq([Kimera::IgnoreList::Shift.new(rule, 3).to_s]))
      expect(resolution.to_h[:stale]).to(be_empty)
    end

    it "leaves a rule stale when its label matches several mutants in the file" do
      rule = { file: "calc.rb", line: 2, label: "< => >" }
      resolution = resolve(rule)
      expect(resolution.to_h.values_at(:ids, :moved, :stale)).to(eq([[], [], [rule]]))
    end

    it "still requires the original snippet and the method when re-anchoring", :aggregate_failures do
      expect(resolve({ file: "calc.rb", line: 2, label: "> => <", original: "x < y" }).to_h[:ids]).to(be_empty)
      expect(resolve({ file: "calc.rb", line: 2, label: "< => >", method: "c" }).to_h[:ids])
        .to(eq([labeled("< => >", 11)]))
    end

    it "re-anchors only rules that carry both a line and a label", :aggregate_failures do
      expect(resolve({ file: "calc.rb", line: 2 }).to_h[:ids]).to(be_empty)
      expect(resolve({ file: "calc.rb", label: "> => <" }).to_h[:moved]).to(be_empty)
    end

    it "keeps a label-less rule stale even when its file holds a single mutant", :aggregate_failures do
      lone = Kimera::RegistryScan.new.source("def m(a)\n  !a\nend\n", file: "lone.rb")
      rule = { file: "lone.rb", line: 9 }
      expect(lone.each.count).to(eq(1))
      expect(described_class.new([rule]).resolve(lone).to_h.values_at(:ids, :stale)).to(eq([[], [rule]]))
    end

    it "leaves stale, rather than re-anchors, rules drifting onto a mutant another rule claims", :aggregate_failures do
      twins = [{ file: "calc.rb", line: 2, label: "> => <" }, { file: "calc.rb", line: 4, label: "> => <" }]
      expect(resolve(*twins).to_h.values_at(:ids, :moved, :stale)).to(eq([[], [], twins]))
      exact = { file: "calc.rb", line: 3, label: "> => <" }
      resolution = resolve(twins.first, exact)
      expect(resolution.to_h.values_at(:ids, :stale)).to(eq([[labeled("> => <", 3)], [twins.first]]))
    end

    it "reports no move for a rule that still matches at its line" do
      expect(resolve({ file: "calc.rb", line: 3, label: "> => <" }).to_h[:moved]).to(be_empty)
    end

    it "unions the ids of several rules on the same file, in id order" do
      first = labeled("> => <", 3)
      last = labeled("< => >", 11)
      rules = [{ file: "calc.rb", line: 11, label: "< => >" }, { file: "calc.rb", line: 3, label: "> => <" }]
      expect(resolve(*rules, rules.first).to_h[:ids]).to(eq([first, last]))
    end
  end
end
