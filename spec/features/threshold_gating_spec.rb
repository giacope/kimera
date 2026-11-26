# frozen_string_literal: true

RSpec.describe("kimera run --max-survivors (threshold gating)") do
  it "passes when survivors are within the threshold" do
    run = test_outcome(cwd: test_sample, arguments: ["--max-survivors", "5", "--no-count-no-coverage"])
    expect([run.counts["survived"], run.status]).to(eq([5, 0]), run.output)
  end

  it "fails when they exceed it" do
    expect(test_outcome(cwd: test_sample, arguments: ["--max-survivors", "2"]).status).to(eq(2))
  end

  describe "skipped source", :aggregate_failures do
    def files
      {
        "app/gate.rb" => "module Gate; def self.open?(value) = value > 5; end\n",
        "spec/gate_spec.rb" => examples
      }
    end

    def examples
      <<~RUBY
        require_relative "../app/gate"
        RSpec.describe Gate do
          it("shuts below 5") { expect(Gate.open?(4)).to be(false) }
          it("shuts at 5") { expect(Gate.open?(5)).to be(false) }
          it("opens above 5") { expect(Gate.open?(6)).to be(true) }
        end
      RUBY
    end

    def skipped(source, *flags)
      test_tree(files.merge("app/skipped.rb" => source)) do |root|
        test_outcome(cwd: root, arguments: ["--operators", "comparison", "--fail-on-no-coverage", *flags])
      end
    end

    ["module Broken\n  def self.unloaded(\nend\n", "VALUES = [1].select { |value| value > 0 }\n"].each do |source|
      it "fails despite killing every generated mutant when the scan skips #{source.lines.first.strip}" do
        run = skipped(source)
        expect(run.counts).to(include("total" => 2, "killed" => 2, "survived" => 0))
        expect(run.report.fetch("unmutated").size).to(eq(1))
        expect([run.status, run.output]).to(match([2, include("gate failed: unmutated=1")]))
      end
    end

    it "keeps the skipped region visible when gating is explicitly disabled" do
      run = skipped("def broken(\n", "--no-gate")
      expect([run.status, run.report.fetch("unmutated").size]).to(eq([0, 1]))
      expect(run.output).not_to(include("gate failed"))
    end

    it "does not gate source explicitly excluded from the scan" do
      run = skipped("def broken(\n", "--exclude", "app/skipped.rb")
      expect([run.status, run.report.fetch("unmutated")]).to(eq([0, []]))
      expect(run.counts).to(include("total" => 2, "killed" => 2))
    end
  end
end
