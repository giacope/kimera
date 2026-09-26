# frozen_string_literal: true

require "json"
require "kimera/registry/builder"
require "kimera/report/formats"
require "kimera/results/run_report"
require "stringio"

RSpec.describe(Kimera::Report::Formats, :aggregate_failures) do
  let(:registry) { Kimera::RegistryScan.new.source("def m(a, b)\n  a > b\nend\n", file: "app/calc.rb") }
  let(:mutant) { registry.each.first.first }
  let(:report) do
    Kimera::RunReport.new(
      registry: registry,
      results: [Kimera::MutantResult.new(mutant_id: mutant.id, status: :survived, file: "app/calc.rb")]
    )
  end

  def output(format)
    io = StringIO.new
    described_class.new(io: io).emit(format, report)
    io.string
  end

  it "emits one parseable JSON document" do
    document = JSON.parse(output("json"))
    expect(document.fetch("results").first).to(include("mutant_id" => mutant.id, "status" => "survived"))
  end

  it "emits newline-delimited summary and result records" do
    records = output("ndjson").lines.map { |line| JSON.parse(line) }
    expect(records.map { |record| record.fetch("type") }).to(eq(%w[summary result]))
  end

  it "emits GitHub workflow annotations" do
    expect(output("github")).to(include("::error file=app/calc.rb,line=2::survived mutant ##{mutant.id}"))
  end

  it "emits a SARIF 2.1.0 document" do
    sarif = JSON.parse(output("sarif"))
    expect(sarif).to(include("version" => "2.1.0"))
    expect(sarif.fetch("runs").first.fetch("results").first.fetch("ruleId")).to(eq("kimera/comparison"))
  end

  it "rejects an unknown format before emitting output" do
    expect { output("xml") }.to(raise_error(Kimera::UsageError, /unknown report format/))
  end
end
