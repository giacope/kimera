# frozen_string_literal: true

require "kimera/results/result"

using ResultFields

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
      noted = result(:killed).with(note: "judged in a fresh isolated mirror")
      expect(noted.to_h).to(include("note" => "judged in a fresh isolated mirror"))
      expect(described_class.from_h(noted.to_h)).to(eq(noted))
    end
  end

  describe "#killing_tests" do
    it "is written and sent only when recorded", :aggregate_failures do
      expect([result(:killed).to_h, result(:killed).message]).to(
        all(
          satisfy do |row|
            !row.key?("killing_tests") && !row.key?(:kills)
          end
        )
      )
      counted = result(:killed).with(killing_tests: %w[t1 t2])
      expect(counted.to_h).to(include("killing_tests" => %w[t1 t2]))
      expect(counted.message).to(include(kills: %w[t1 t2]))
      expect(counted.waive.killing_tests).to(eq(%w[t1 t2]))
    end
  end

  describe "#unjudged" do
    it "keeps only the identity, with the reason as detail" do
      judged = result(:killed).with(failing_tests: ["t1"]).unjudged("its tests fail")
      expected = described_class.new(mutant_id: 1, status: :harness_error, file: "x.rb", detail: "its tests fail")
      expect(judged).to(eq(expected))
    end
  end

  describe "#waive" do
    it "keeps the evaluation but reports the mutant as ignored with its verdict", :aggregate_failures do
      waived = result(:killed).with(detail: "Calc spec failed").waive
      expect(waived).to(have_fields(mutant_id: 1, status: :ignored, verdict: :killed, file: "x.rb", duration: 0.1))
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
      expect(described_class.from_waiver(1, "x.rb").lapsed?).to(be(false))
    end
  end

  describe "what other objects ask of a result" do
    let(:judged) do
      described_class.new(
        mutant_id: 4, status: :survived, file: "x.rb", failing_tests: ["f1"], covering_tests: ["c1"], detail: "warm"
      )
    end

    it "keeps its fields to itself" do
      expect(described_class.members.select { |field| judged.public_methods.include?(field) }).to(eq([]))
    end

    it "keys itself by its mutant, and looks itself up in a table keyed so", :aggregate_failures do
      expect(judged.entry).to(eq([4, judged]))
      expect(judged.from(4 => :point)).to(eq(:point))
      expect { judged.from({}) }.to(raise_error(KeyError))
    end

    it "orders by mutant id" do
      expect([judged, result(:killed)].sort.map(&:mutant_id)).to(eq([1, 4]))
    end

    it "tells whether its status is one of those named", :aggregate_failures do
      expect([judged.status?(:survived), judged.status?(:killed, :survived), judged.status?(:killed)])
        .to(eq([true, true, false]))
    end

    it "ticks a progress with its status, and hands its covering tests on", :aggregate_failures do
      expect(judged.tick(->(status) { [:ticked, status] })).to(eq(%i[ticked survived]))
      expect(judged.covering { |tests| [:ran, tests] }).to(eq([:ran, ["c1"]]))
    end

    it "is unstaged with its detail after the reason" do
      expect(judged.unstaged("could not stage it: "))
        .to(have_fields(mutant_id: 4, status: :harness_error, detail: "could not stage it: warm"))
    end

    it "credits the killing tests its block names from its id and failing tests", :aggregate_failures do
      expect(judged.credit { |id, failing| [id, *failing] }.killing_tests).to(eq([4, "f1"]))
      expect(result(:killed).credit { |_id, failing| failing }.killing_tests).to(eq([]))
    end

    it "is quarantined when its status is suspect and its block gives a reason", :aggregate_failures do
      reasons = []
      suspected = judged.suspected(%i[timeout survived]) { |status, file| reasons.push([status, file]) && "why" }
      expect([suspected.status, suspected.detail, reasons]).to(eq([:isolated_only, "why", [[:survived, "x.rb"]]]))
      expect(judged.suspected(%i[timeout survived]) { false }).to(be(judged))
      expect(judged.suspected([:timeout]) { raise(KeyError, "not asked") }).to(be(judged))
    end

    it "merges a fresh verdict, keeping both sides' tests" do
      fresh = result(:killed).with(failing_tests: %w[f2 c1])
      expect(judged.merged(fresh)).to(eq(fresh.with(covering_tests: %w[c1 f2])))
    end

    it "merges an unjudged verdict, keeping a kill or its own survival", :aggregate_failures do
      unjudged = result(:harness_error).with(failing_tests: ["f3"])
      expect(judged.merged(unjudged)).to(eq(unjudged.with(covering_tests: %w[c1 f3])))
      uncovered = judged.with(status: :no_coverage)
      expect(uncovered.merged(unjudged)).to(eq(uncovered.with(covering_tests: %w[c1 f3])))
    end

    it "notes on a verdict why it was judged again, with its own detail" do
      expect(judged.noting(result(:killed), "again: ")).to(eq(result(:killed).with(note: "again: warm")))
    end

    it "reads back the killing tests it was saved with" do
      counted = result(:killed).with(killing_tests: ["k1"])
      expect(described_class.from_h(counted.to_h)).to(eq(counted))
    end

    it "keeps its raw duration but reports none as zero", :aggregate_failures do
      timeless = described_class.new(mutant_id: 2, status: :killed, file: "x.rb")
      expect([timeless.to_h["duration"], timeless.message[:ms], timeless.waive.to_h["duration"]])
        .to(eq([0.0, 0.0, 0.0]))
      expect(timeless.isolated("why").to_h["duration"]).to(eq(0.0))
      expect(timeless.inspect).to(include("duration=nil"))
    end
  end

  describe Kimera::LeakReport do
    let(:leak) { described_class.new(mutant_id: 3, detail: "state") }

    it "prints its line, tells whether a table holds its mutant, and keeps its fields", :aggregate_failures do
      expect(leak.line).to(eq("- #3  state"))
      expect([leak.among?(3 => :kept), leak.among?(4 => :kept)]).to(eq([true, false]))
      expect(
        [
          leak.public_methods.intersect?(%i[mutant_id detail]),
          leak.to_h
        ]
      ).to(eq([false, { mutant_id: 3, detail: "state" }]))
    end
  end
end
