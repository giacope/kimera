# frozen_string_literal: true

require "kimera/results/result"

RSpec.describe(Kimera::MutantResult) do
  def result(status)
    described_class.new(mutant_id: 1, status: status, file: "x.rb", duration: 0.1)
  end

  describe "#killed?" do
    it "is true for killed, timeout, and error" do
      %i[killed timeout error].each { |s| expect(result(s).killed?).to(be(true)) }
    end

    it "is false for survived, no_coverage, and ignored" do
      %i[survived no_coverage ignored].each { |s| expect(result(s).killed?).to(be(false)) }
    end
  end

  describe "#covered?" do
    it "excludes no_coverage and ignored, includes the rest", :aggregate_failures do
      expect(result(:killed).covered?).to(be(true))
      expect(result(:survived).covered?).to(be(true))
      expect(result(:no_coverage).covered?).to(be(false))
      expect(result(:ignored).covered?).to(be(false))
    end
  end

  describe "serialization" do
    let(:original) do
      described_class.new(
        mutant_id: 7, status: :survived, file: "a.rb", duration: 1.5,
        failing_tests: ["t1"], covering_tests: ["t2"], detail: "note"
      )
    end

    let(:reloaded) { described_class.from_h(original.to_h) }

    it "round-trips the scalar fields", :aggregate_failures do
      expect(reloaded.mutant_id).to(eq(7))
      expect(reloaded.status).to(eq(:survived))
      expect(reloaded.file).to(eq("a.rb"))
      expect(reloaded.duration).to(eq(1.5))
    end

    it "round-trips the list and detail fields", :aggregate_failures do
      expect(reloaded.failing_tests).to(eq(["t1"]))
      expect(reloaded.covering_tests).to(eq(["t2"]))
      expect(reloaded.detail).to(eq("note"))
    end

    it "serializes status as a string" do
      expect(result(:killed).to_h["status"]).to(eq("killed"))
    end

    it "writes a verdict only for an evaluated ignored mutant, and reads it back", :aggregate_failures do
      expect(original.to_h).not_to(have_key("verdict"))
      expect(reloaded.verdict).to(be_nil)
      waived = original.waive
      expect(waived.to_h).to(include("status" => "ignored", "verdict" => "survived"))
      expect(described_class.from_h(waived.to_h)).to(eq(waived))
    end
  end

  describe "#note" do
    it "is written only when set, and read back", :aggregate_failures do
      expect(result(:killed).to_h).not_to(have_key("note"))
      noted = result(:killed).tap { |killed| killed.note = "judged in a fresh isolated mirror" }
      expect(noted.to_h).to(include("note" => "judged in a fresh isolated mirror"))
      expect(described_class.from_h(noted.to_h)).to(eq(noted))
    end
  end

  describe "#unjudged" do
    it "keeps only the identity, with the reason as detail" do
      judged = result(:killed).tap { |killed| killed.failing_tests = ["t1"] }.unjudged("its tests fail")
      expected = described_class.new(mutant_id: 1, status: :harness_error, file: "x.rb", detail: "its tests fail")
      expect(judged).to(eq(expected))
    end
  end

  describe "#waive" do
    it "keeps the evaluation but reports the mutant as ignored with its verdict", :aggregate_failures do
      waived = result(:killed).tap { |killed| killed.detail = "Calc spec failed" }.waive
      expect(waived).to(have_attributes(mutant_id: 1, status: :ignored, verdict: :killed, file: "x.rb", duration: 0.1))
      expect(waived.detail).to(eq("ignored (killed): Calc spec failed"))
      expect(result(:survived).waive.detail).to(eq("ignored (survived)"))
    end

    it "never counts toward the score or the kills" do
      expect([result(:killed).waive.covered?, result(:killed).waive.killed?]).to(eq([false, false]))
    end
  end

  describe "#lapsed?" do
    it "is true only for an ignored mutant whose verdict is a kill", :aggregate_failures do
      %i[killed timeout error].each { |s| expect(result(s).waive.lapsed?).to(be(true)) }
      %i[survived no_coverage harness_error].each { |s| expect(result(s).waive.lapsed?).to(be(false)) }
      expect(described_class.waived(1, "x.rb").lapsed?).to(be(false))
    end
  end
end
