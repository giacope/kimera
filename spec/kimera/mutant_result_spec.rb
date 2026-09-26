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
  end
end
