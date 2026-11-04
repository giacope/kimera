# frozen_string_literal: true

require "fileutils"
require "kimera/cli"
require "kimera/results/run_report"
require "tmpdir"

# A narrowed run cannot know whether a test it left out covers a mutant: its
# uncovered rows say so, and only on a narrowed run.
RSpec.describe(Kimera::CLI::Run::Cycle, "#narrowed") do
  around { |example| Dir.mktmpdir { |dir| Dir.chdir(dir) { example.run } } }

  before do
    FileUtils.mkdir_p("spec")
    %w[a b].each { |name| File.write("spec/#{name}_spec.rb", "") }
  end

  def report
    Kimera::RunReport.new(
      results: [
        Kimera::MutantResult.new(mutant_id: 1, status: :no_coverage, file: "a.rb"),
        Kimera::MutantResult.new(mutant_id: 2, status: :no_coverage, file: "a.rb", detail: "reached only at load"),
        Kimera::MutantResult.new(mutant_id: 3, status: :survived, file: "a.rb")
      ]
    )
  end

  # A run of the configured spec/*_spec.rb, or of only spec/a_spec.rb when +narrowed+.
  def details(narrowed)
    tests = narrowed ? ["spec/a_spec.rb"] : ["spec/*_spec.rb"]
    options = { tests: tests, configured_tests: ["spec/*_spec.rb"], exclude_tests: [] }
    described_class.new(options, nil, digest: nil).__send__(:narrowed, report).results.map(&:detail)
  end

  it "says an uncovered mutant is not covered by the narrowed tests, keeping a reason it already has" do
    expect(details(true)).to(eq([described_class::NARROWED, "reached only at load", nil]))
  end

  it "leaves a full run's rows as they are" do
    expect(details(false)).to(eq([nil, "reached only at load", nil]))
  end
end
