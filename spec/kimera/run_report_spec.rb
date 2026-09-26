# frozen_string_literal: true

require "fileutils"
require "kimera/registry/builder"
require "kimera/results/run_report"
require "tmpdir"

RSpec.describe(Kimera::RunReport) do
  def result(id, status)
    Kimera::MutantResult.new(mutant_id: id, status: status, file: "x.rb", duration: 0.1)
  end

  subject(:report) { described_class.new(results: results) }

  let(:results) do
    [
      result(1, :killed), result(2, :killed), result(3, :survived),
      result(4, :timeout), result(5, :error), result(6, :no_coverage),
      result(7, :ignored)
    ]
  end

  describe "status partitions" do
    it "groups by status and via the killed/survived/no_coverage helpers", :aggregate_failures do
      expect(report.killed.map(&:mutant_id)).to(contain_exactly(1, 2, 4, 5))
      expect(report.survived.map(&:mutant_id)).to(contain_exactly(3))
      expect(report.uncovered.map(&:mutant_id)).to(contain_exactly(6))
      expect(report.statuses(:ignored).map(&:mutant_id)).to(contain_exactly(7))
    end

    it "treats killed/timeout/error/survived as evaluable; not no_coverage/ignored" do
      expect(report.covered.map(&:mutant_id)).to(contain_exactly(1, 2, 3, 4, 5))
    end
  end

  describe "#score" do
    it "is killed / evaluable" do
      # 4 killed out of 5 evaluable
      expect(report.score).to(be_within(1e-9).of(4.0 / 5))
    end

    it "is 1.0 when there is nothing to evaluate" do
      empty = described_class.new(results: [result(1, :no_coverage)])
      expect(empty.score).to(eq(1.0))
    end
  end

  describe "#counts and #summary" do
    let(:leak) { Kimera::LeakReport.new(mutant_id: 1, detail: "leak") }
    let(:rep_with_leak) { described_class.new(results: results, leaks: [leak]) }

    def counts
      {
        total: 7, killed: 4, survived: 1, timeout: 1, error: 1,
        no_coverage: 1, harness_error: 0, ignored: 1, isolated_only: 0, leaks: 1
      }
    end

    def tokens
      ["mutants=7", "killed=4", "survived=1", "timeout=1", "error=1", "no_coverage=1", "ignored=1", "leaks=1"]
    end

    it "counts each status plus leaks" do
      expect(rep_with_leak.counts).to(eq(counts))
    end

    it "renders a summary line naming each status count" do
      expect(rep_with_leak.summary).to(include(*tokens))
    end

    it "renders a summary line with the score" do
      expect(rep_with_leak.summary).to(include("score=80.0%"))
    end

    # Otherwise a run that killed nothing could read 100%.
    it "annotates the score with the uncovered count" do
      expect(report.summary).to(include("score=80.0% (1 uncovered not scored)"))
    end

    it "leaves the score unannotated when every mutant was covered", :aggregate_failures do
      rep = described_class.new(results: [result(1, :killed)])
      expect(rep.summary).to(include("score=100.0%"))
      expect(rep.summary).not_to(include("uncovered"))
    end

    it "reports score=n/a when mutants exist but none were evaluated" do
      rep = described_class.new(results: [result(1, :no_coverage), result(2, :no_coverage)])
      expect(rep.summary).to(include("score=n/a (0 of 2 mutants evaluated)"))
    end

    it "omits ignored, isolated_only, and leaks from the summary when there are none", :aggregate_failures do
      rep = described_class.new(results: [result(1, :killed)])
      expect(rep.summary).not_to(include("ignored="))
      expect(rep.summary).not_to(include("isolated_only="))
      expect(rep.summary).not_to(include("leaks="))
      expect(rep.summary).not_to(include("unjudged="))
    end

    describe "unjudged mutants" do
      let(:unjudged) { [result(1, :killed), result(2, :harness_error)] }

      it "keeps them out of both the numerator and the denominator", :aggregate_failures do
        rep = described_class.new(results: unjudged)
        expect(rep.score).to(eq(1.0))
        expect(rep.killed.map(&:mutant_id)).to(eq([1]))
        expect(rep.covered.map(&:mutant_id)).to(eq([1]))
      end

      it "counts and announces them", :aggregate_failures do
        rep = described_class.new(results: unjudged)
        expect(rep.errors.map(&:mutant_id)).to(eq([2]))
        expect(rep.counts[:harness_error]).to(eq(1))
        expect(rep.summary).to(include("unjudged=1"))
      end
    end
  end

  describe "#to_h" do
    describe "top-level fields" do
      let(:leak) { Kimera::LeakReport.new(mutant_id: 1, detail: "leak") }
      let(:h) { described_class.new(results: [result(1, :killed)], leaks: [leak]).to_h }

      it "includes the schema version and counts", :aggregate_failures do
        expect(h["schema_version"]).to(eq(described_class::SCHEMA_VERSION))
        expect(h["counts"][:killed]).to(eq(1))
      end

      it "includes the score, results, and leaks", :aggregate_failures do
        expect(h["mutation_score"]).to(eq(1.0))
        expect(h["results"].first["mutant_id"]).to(eq(1))
        expect(h["leaks"].first[:detail]).to(eq("leak"))
      end
    end

    describe "enrichment from a registry" do
      let(:dir) { Dir.mktmpdir }
      let(:registry) do
        path = File.join(dir, "cmp.rb")
        File.write(path, "class Cmp\n  def gt(a, b)\n    a > b\n  end\nend\n")
        Kimera::RegistryScan.new(root: dir).build([path])
      end
      let(:mutant_and_point) { registry.each.first }
      let(:enriched) do
        mutant = mutant_and_point.first
        described_class.new(results: [result(mutant.id, :survived)], registry: registry).to_h["results"].first
      end

      after { FileUtils.remove_entry(dir) }

      it "carries line, operator, and label", :aggregate_failures do
        mutant, point = mutant_and_point
        expect(enriched["line"]).to(eq(point.location.start_line))
        expect(enriched["operator"]).to(eq(point.operator))
        expect(enriched["label"]).to(eq(mutant.label))
      end

      it "carries the original->mutated diff", :aggregate_failures do
        point = mutant_and_point.last
        expect(enriched["original"]).to(eq(point.original_source))
        expect(enriched["mutated"]).to(be_a(String))
      end
    end

    it "leaves a result unenriched when its mutant id is not in the registry" do
      registry = Kimera::RegistryScan.new
        .source("def gt(a, b)\n  a > b\nend\n", file: "cmp.rb")
      h = described_class.new(results: [result(999_999, :survived)], registry: registry).to_h
      expect(h["results"].first).not_to(have_key("line"))
    end

    it "omits enrichment fields when no registry is available" do
      expect(described_class.new(results: [result(1, :survived)]).to_h["results"].first).not_to(have_key("line"))
    end
  end
end
