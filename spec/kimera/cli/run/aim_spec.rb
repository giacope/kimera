# frozen_string_literal: true

require "kimera/cli/run"
require "kimera/registry/builder"

RSpec.describe(Kimera::CLI::Run::Aim) do
  let(:registry) do
    Kimera::RegistryScan.new.source(<<~RUBY, file: "calc.rb")
      class Calc
        def low(x)
          x < 1
        end

        def high(x)
          x > 9
        end
      end
    RUBY
  end
  let(:all) { registry.index.keys }

  def aimed(**options) = described_class.new(registry, { source_root: "." }.merge(options)).restrict(all)

  def lines_of(ids) = ids.map { |id| registry.index.fetch(id).location.start_line }.uniq

  it "keeps every mutant when nothing is aimed at" do
    expect(aimed).to(eq(all))
  end

  it "keeps the mutants on the lines a path names, relative to the source root", :aggregate_failures do
    expect(lines_of(aimed(lines: { "calc.rb" => Set[3] }))).to(eq([3]))
    expect(lines_of(aimed(lines: { "./calc.rb" => Set[2, 3, 4, 5, 6, 7] }))).to(eq([3, 7]))
  end

  it "leaves files the lines do not name untouched" do
    expect(aimed(lines: { "other.rb" => Set[1] })).to(eq(all))
  end

  it "keeps the mutants inside the named methods, and only the ids it was given", :aggregate_failures do
    expect(lines_of(aimed(methods: ["high"]))).to(eq([7]))
    kept = described_class.new(registry, { source_root: ".", methods: %w[low high] }).restrict(all.first(1))
    expect(kept).to(eq(all.first(1)))
  end

  it "names what it aimed at and what it could have hit when nothing matches" do
    expect { aimed(lines: { "calc.rb" => Set[4, 5] }, methods: ["nope"]) }.to(
      raise_error(
        Kimera::UsageError,
        "no mutants match calc.rb:4-5 and method nope " \
          "(mutated lines in calc.rb: 3, 7; methods with mutants: high, low)"
      )
    )
  end

  it "names a single line without a range, and an unscanned file as having none" do
    expect { aimed(lines: { "calc.rb" => Set[5], "gone.rb" => Set[1] }) }.to(
      raise_error(
        Kimera::UsageError,
        "no mutants match calc.rb:5 and gone.rb:1 (mutated lines in calc.rb: 3, 7; mutated lines in gone.rb: none)"
      )
    )
  end
end
