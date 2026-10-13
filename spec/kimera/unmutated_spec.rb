# frozen_string_literal: true

require "kimera/registry/builder"
require "kimera/report/text"
require "kimera/results/run_report"
require "stringio"

RSpec.describe(Kimera::Unmutated) do
  let(:registry) { Kimera::RegistryScan.new.source("class W\n  X = [1].map { |n| n > 0 }\nend\n", file: "w.rb") }

  let(:report) { Kimera::RunReport.new(results: [], registry: registry) }

  it "lists each region with its reason in the text report" do
    io = StringIO.new
    Kimera::Report::Text.new(registry, io: io, color: false).report(report)
    expect(io.string).to(include("\nNot mutated (1 region(s)):\n  w.rb:2  #{Kimera::Unmutated::BLOCK}\n"))
  end

  it "lists them in the JSON report" do
    expect(report.to_h["unmutated"]).to(
      eq([{ "file" => "w.rb", "start_line" => 2, "end_line" => 2, "reason" => Kimera::Unmutated::BLOCK }])
    )
  end

  it "prints no section when everything scanned was mutated" do
    io = StringIO.new
    clean = Kimera::RegistryScan.new.source("def a(x) = x > 1\n", file: "a.rb")
    Kimera::Report::Text.new(clean, io: io, color: false).report(Kimera::RunReport.new(results: [], registry: clean))
    expect(io.string).not_to(include("Not mutated"))
  end

  it "names a multi-line region by its first and last line" do
    expect(described_class.new("w.rb", 3, 5, "why").place).to(eq("w.rb:3-5"))
  end
end
