# frozen_string_literal: true

require "kimera/cli"
require "kimera/results/run_report"

# A narrowed run cannot know whether a test it left out covers a mutant: its
# uncovered rows say so, and only on a narrowed run.
RSpec.describe(Kimera::CLI::Run::Cycle, "#narrowed") do
  def report
    Kimera::RunReport.new(
      results: [
        Kimera::MutantResult.new(mutant_id: 1, status: :no_coverage, file: "a.rb"),
        Kimera::MutantResult.new(mutant_id: 2, status: :no_coverage, file: "a.rb", detail: "reached only at load"),
        Kimera::MutantResult.new(mutant_id: 3, status: :survived, file: "a.rb")
      ]
    )
  end

  def details(narrowed)
    cycle = described_class.new({}, nil, nil, digest: nil)
    allow(cycle).to(receive(:narrowing).and_return(instance_double(Kimera::CLI::Run::Narrowing, narrowed?: narrowed)))
    cycle.__send__(:narrowed, report).results.map(&:detail)
  end

  it "says an uncovered mutant is not covered by the narrowed tests, keeping a reason it already has" do
    expect(details(true)).to(eq([described_class::NARROWED, "reached only at load", nil]))
  end

  it "leaves a full run's rows as they are" do
    expect(details(false)).to(eq([nil, "reached only at load", nil]))
  end
end
