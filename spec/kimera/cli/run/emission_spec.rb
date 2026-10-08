# frozen_string_literal: true

require "kimera/cli/run"
require "kimera/registry/builder"
require "stringio"
require "tmpdir"

RSpec.describe(Kimera::CLI::Run::Emission, :aggregate_failures) do
  let(:registry) { Kimera::RegistryScan.new.source("def m(a, b)\n  a > b\nend\n", file: "calc.rb") }
  let(:report) do
    survivor = Kimera::MutantResult.new(mutant_id: registry.each.first.first.id, status: :survived, file: "calc.rb")
    Kimera::RunReport.new(results: [survivor], registry: registry)
  end
  let(:narration) { StringIO.new }
  let(:output) { StringIO.new }

  def emit(**settings) = described_class.new(io: narration, output: output).emit(report, registry, **settings)

  it "narrates the text report beside GitHub annotations, so the job log reads on its own" do
    emit(format: "github")
    expect(narration.string).to(start_with("mutants=1 killed=0 survived=1"))
    expect(output.string).to(start_with("::error file=calc.rb,line=2"))
  end

  it "keeps the narration out of the other machine formats, and quiet silences it" do
    emit(format: "json")
    expect(narration.string).to(eq(""))
    described_class.new(io: narration, output: output, quiet: true).emit(report, registry, format: "github")
    expect(narration.string).to(eq(""))
  end

  it "appends a Markdown summary to the file --summary names, creating its directory" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "steps/summary.md")
      emit(summary: path)
      emit(summary: path)
      expect(File.read(path).scan("### Kimera: 1 surviving of 1 mutants (score 0.0%)").size).to(eq(2))
    end
  end
end
