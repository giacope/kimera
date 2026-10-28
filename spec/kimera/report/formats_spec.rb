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

  it "emits a GitHub annotation per line, titled and placed by column, with the diff" do
    annotation = "::error file=app/calc.rb,line=2,col=3,title=Kimera%3A 1 surviving mutant(s)::" \
      "survived mutant ##{mutant.id} at app/calc.rb:2: > => >=%0A- a > b%0A+ a >= b\n"
    expect(output("github")).to(eq(annotation))
  end

  it "emits a SARIF 2.1.0 document, with the region's columns and the diff in the message" do
    sarif = JSON.parse(output("sarif"))
    result = sarif.fetch("runs").first.fetch("results").first
    expect([sarif["version"], result.fetch("ruleId"), result.dig("locations", 0, "physicalLocation", "region")]).to(
      eq(["2.1.0", "kimera/comparison", { "startLine" => 2, "startColumn" => 3, "endLine" => 2, "endColumn" => 8 }])
    )
    expect(result.dig("message", "text")).to(end_with("> => >=\n- a > b\n+ a >= b"))
  end

  it "renders a Markdown summary of what the run found" do
    expect(output("markdown")).to(eq(<<~MARKDOWN))
      ### Kimera: 1 surviving of 1 mutants (score 0.0%)

      | | Where | Mutation |
      |---|---|---|
      | Surviving | `app/calc.rb:2` in `m` | `a > b` → `a >= b` |
    MARKDOWN
  end

  context "with several findings" do
    let(:registry) do
      Kimera::RegistryScan.new.source("def m(a, b)\n  a > b\nend\n\ndef n(a)\n  a || b\nend\n", file: "app/calc.rb")
    end
    let(:report) do
      status = ->(point) { point.location.start_line == 2 ? :survived : :no_coverage }
      results = registry.each.map { |found, point| Kimera::MutantResult.new(mutant_id: found.id, status: status.call(point)) }
      Kimera::RunReport.new(registry: registry, results: results.each { |result| result.file = "app/calc.rb" })
    end

    it "folds the mutants on one line into one annotation, a warning for uncovered ones", :aggregate_failures do
      lines = output("github").lines
      expect(lines.size).to(eq(2))
      expect(lines.first).to(start_with("::error file=app/calc.rb,line=2,col=3,title=Kimera%3A 2 surviving mutant(s)"))
      expect(lines.first).to(include("%0A%0Asurvived mutant"))
      expect(lines.last).to(start_with("::warning file=app/calc.rb,line=6,col=3,title=Kimera%3A 1 uncovered mutant(s)"))
    end

    it "annotates a mutant only other units' tests reach as an error, like a survivor", :aggregate_failures do
      results = report.results.map { |result| result.dup.tap { |copy| copy.status = :uncovered_by_unit } }
      lines = emitted("github", Kimera::RunReport.new(registry: registry, results: results)).lines
      title = "title=Kimera%3A 2 unit-uncovered mutant(s)"
      expect(lines.first).to(start_with("::error file=app/calc.rb,line=2,col=3,#{title}"))
      expect(lines.last).to(start_with("::error file=app/calc.rb,line=6,col=3,#{title.sub("2", "1")}"))
    end

    it "lists uncovered mutants in the Markdown summary, escaping pipes" do
      expect(output("markdown")).to(include("| Uncovered | `app/calc.rb:6` in `n` | `a \\|\\| b` → `(a && b)` |"))
    end
  end

  # R6B6-M3: a mutant whose text kimera could not write says so, not a lone `-` line.
  it "leaves out the column and diff a bare result does not carry", :aggregate_failures do
    bare = { "mutant_id" => 4, "status" => "survived", "file" => "a.rb", "line" => 3, "label" => "x" }
    io = StringIO.new
    described_class.new(io: io).render("github", { "results" => [bare, bare.merge("line" => 5, "original" => "y")] })
    expect(io.string.lines).to(
      eq(
        [
          "::error file=a.rb,line=3,title=Kimera%3A 1 surviving mutant(s)::survived mutant #4 at a.rb:3: x\n",
          "::error file=a.rb,line=5,title=Kimera%3A 1 surviving mutant(s)::survived mutant #4 at a.rb:5: x%0A- y" \
            "%0A+ #{Kimera::Rewrite::MutantText::UNWRITTEN}\n"
        ]
      )
    )
  end

  def emitted(format, run) = StringIO.new.tap { |io| described_class.new(io: io).emit(format, run) }.string

  def rendered(format, document) = StringIO.new.tap { |io| described_class.new(io: io).render(format, document) }.string

  # Findings on lines 1 to count of a.rb.
  def findings(count, **row)
    (1..count).map { |line| { "file" => "a.rb", "line" => line }.merge(row.transform_keys(&:to_s)) }
  end

  it "says when GitHub will show only some of the annotations" do
    lines = rendered("github", "results" => findings(11, status: "survived", label: "x")).lines
    notice = "::notice title=Kimera::11 annotations; GitHub shows 10 of each level per step. " \
      "The job summary and the JSON report list every finding.\n"
    expect([lines.size, lines.last]).to(eq([12, notice]))
  end

  it "adds no notice for ten annotations" do
    expect(rendered("github", "results" => findings(10, status: "survived", label: "x"))).not_to(include("::notice"))
  end

  def calm = { "counts" => { "total" => 2, "killed" => 0, "survived" => 0 }, "mutation_score" => 1.0, "results" => [] }

  it "renders a Markdown summary without findings" do
    expect(rendered("markdown", calm))
      .to(eq("### Kimera: 0 surviving of 2 mutants\n\nEvery mutant in scope was killed.\n"))
  end

  it "renders a Markdown summary past fifty findings", :aggregate_failures do
    shown = rendered("markdown", calm.merge("results" => findings(51, status: "harness_error", detail: "a|b")))
    expect(shown).to(include("| Unjudged | `a.rb:1` | a\\|b |", "…and 1 more; the JSON report lists every one."))
    expect(shown).not_to(include("`a.rb:51`"))
  end

  context "with a mutant judged again in a fresh mirror" do
    let(:report) do
      noted = Kimera::MutantResult.new(mutant_id: mutant.id, status: :survived, file: "app/calc.rb", note: "50%")
      Kimera::RunReport.new(registry: registry, results: [noted])
    end

    it "keeps the note in the JSON and ndjson records" do
      expect(JSON.parse(output("json")).fetch("results").first).to(include("note" => "50%"))
      expect(JSON.parse(output("ndjson").lines.last)).to(include("type" => "result", "note" => "50%"))
    end

    it "appends the note to the GitHub annotation and the SARIF message" do
      noted = "::survived mutant ##{mutant.id} at app/calc.rb:2: > => >= (50%25)%0A- a > b%0A+ a >= b\n"
      expect(output("github")).to(end_with(noted))
      message = JSON.parse(output("sarif")).fetch("runs").first.fetch("results").first.dig("message", "text")
      expect(message).to(eq("survived mutant ##{mutant.id} at app/calc.rb:2: > => >= (50%)\n- a > b\n+ a >= b"))
    end
  end

  it "rejects an unknown format before emitting output" do
    expect { output("xml") }.to(raise_error(Kimera::UsageError, /unknown report format/))
  end
end
