# frozen_string_literal: true

require "kimera/report/file_table"
require "kimera/results/run_report"
require "stringio"

RSpec.describe(Kimera::Report::FileTable) do
  def table(files)
    results = (1..files).map { |n| Kimera::MutantResult.new(mutant_id: n, status: :killed, file: "f#{n}.rb") }
    io = StringIO.new
    described_class.new(io: io).show(Kimera::RunReport.new(results: results))
    io.string
  end

  it "lists up to fifteen files with no remainder note", :aggregate_failures do
    shown = table(15)
    expect(shown).to(include("Files (15, most survivors first):", "f15.rb"))
    expect(shown).not_to(include("more files"))
  end

  it "notes the files past the fifteenth", :aggregate_failures do
    shown = table(16)
    expect(shown).to(end_with("  (+1 more files)\n"))
    expect(shown.lines.size).to(eq(19))
  end
end
