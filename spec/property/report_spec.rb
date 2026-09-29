# frozen_string_literal: true

require "json"
require "stringio"
require "kimera/cli"
require "kimera/cli/run"
require "kimera/cli/run/gate"
require "kimera/report/tally"
require "kimera/results/run_report"
require_relative "property_helper"

RSpec.describe(Kimera::RunReport) do
  let(:statuses) { Pbt.one_of(:killed, *Kimera::Status::REPORTED) }
  let(:results) { Pbt.array(statuses, max: 30) }

  def report(outcomes)
    Kimera::RunReport.new(
      results: outcomes.each_with_index.map do |status, i|
        Kimera::MutantResult.new(mutant_id: i + 1, status: status, file: "x.rb", duration: 0.5)
      end
    )
  end

  def score(outcomes)
    covered = outcomes.count { |status| !Kimera::Status::UNJUDGED.include?(status) }
    killed = outcomes.count { |status| Kimera::Status::KILLING.include?(status) }
    covered.zero? ? 1.0 : Float(killed) / covered
  end

  def reloaded(subject) = JSON.parse(JSON.generate(subject.to_h))["results"].map { Kimera::MutantResult.from_h(it) }

  it "scores killed over covered, counts every result once, and survives JSON" do
    for_all(results, runs: 300) do |outcomes|
      subject = report(outcomes)
      counts = subject.counts
      expect(subject.score).to(eq(score(outcomes)))
      expect(counts[:total]).to(eq(outcomes.size))
      expect(counts.slice(*Kimera::Status::REPORTED).values.sum + outcomes.count(:killed)).to(eq(outcomes.size))
      expect(reloaded(subject).map(&:status)).to(eq(outcomes))
    end
  end

  describe Kimera::CLI::Run::Gate do
    let(:options) do
      Pbt.fixed_hash(
        max_survivors: Pbt.one_of(nil, 0, 1, 3), max_ignored: Pbt.one_of(nil, 0, 2),
        max_errors: Pbt.one_of(nil, 0, 2), fail_on_no_coverage: Pbt.boolean
      )
    end

    def status(outcomes, options) = described_class.new(report(outcomes), options).status(StringIO.new)

    # More bad news never makes a failing gate pass.
    it "exits 0 or 2, and a failing gate never passes once another result lands" do
      for_all(results, options, statuses, runs: 300) do |outcomes, options, extra|
        before = status(outcomes, options)
        expect(before).to(eq(0).or(eq(2)))
        expect(status(outcomes + [extra], options)).to(eq(2), "#{extra} turned the gate green") if before == 2
      end
    end
  end

  describe Kimera::Report::Tally do
    it "draws a bar of fixed width at every point of a run" do
      for_all(Pbt.integer(min: 1, max: 5000), Pbt.array(statuses, max: 60), runs: 300) do |total, ticks|
        tally = described_class.new
        tally.begin!(total, "mutants", 0.0)
        ticks.first(total).each_with_index do |status, i|
          tally.count!(status)
          expect(tally.line(i + 1.5)[/\[[^\]]*\]/].size).to(eq(described_class::BAR_WIDTH + 2))
        end
      end
    end
  end
end
