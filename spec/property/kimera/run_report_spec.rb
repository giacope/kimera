# frozen_string_literal: true

require "json"
require "stringio"
require "kimera/cli"
require "kimera/cli/run"
require "kimera/cli/run/gate"
require "kimera/report/tally"
require "kimera/results/run_report"
require_relative "../property_helper"

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

  # A report's score, total, statuses counted, and statuses after JSON, then what they must be.
  def accounting(outcomes)
    run = report(outcomes)
    counts = run.counts
    facts = {
      score: run.score, total: counts[:total],
      counted: counts.slice(*Kimera::Status::REPORTED).values.sum + outcomes.count(:killed),
      reloaded: reloaded(run).map(&:status)
    }
    [facts, { score: score(outcomes), total: outcomes.size, counted: outcomes.size, reloaded: outcomes }]
  end

  it "scores killed over covered, counts every result once, and survives JSON" do
    for_all(results, runs: 300) do |outcomes|
      facts, expected = accounting(outcomes)
      expect(facts).to(eq(expected))
    end
  end

  describe Kimera::CLI::Run::Gate do
    let(:options) do
      Pbt.fixed_hash(
        max_survivors: Pbt.one_of(nil, 0, 1, 3), max_ignored: Pbt.one_of(nil, 0, 2),
        max_errors: Pbt.one_of(nil, 0, 2), fail_on_no_coverage: Pbt.boolean, count_no_coverage: Pbt.boolean
      )
    end

    def status(outcomes, options) = described_class.new(report(outcomes), options).status(StringIO.new)

    # The gate's documented rules (README, `kimera help run`), restated.
    def failing?(outcomes, options)
      survived, uncovered, ignored, unjudged = %i[survived no_coverage ignored harness_error].map { outcomes.count(it) }
      survived += outcomes.count(:uncovered_by_unit)
      cap = options[:max_survivors]
      [
        cap ? survived > cap : survived.positive?,
        (options[:fail_on_no_coverage] || options[:count_no_coverage]) && uncovered.positive?,
        options[:max_ignored] && ignored > options[:max_ignored],
        unjudged > (options[:max_errors] || 0),
        untested?(outcomes)
      ].any?
    end

    # Nothing killed while mutants only the isolated tier can judge wait.
    def untested?(outcomes)
      outcomes.intersect?(%i[isolated_only unmutatable]) && !outcomes.intersect?(Kimera::Status::KILLING)
    end

    it "exits 2 exactly when a documented threshold is crossed, and 0 otherwise" do
      for_all(results, options, runs: 500) do |outcomes, options|
        expect(status(outcomes, options)).to(eq(failing?(outcomes, options) ? 2 : 0))
      end
    end

    # More bad news never makes a failing gate pass. A kill is good news: it
    # is the evaluation an all-isolated_only run was missing.
    it "never passes once another result lands on a failing gate" do
      bad = Pbt.one_of(*(Kimera::Status::REPORTED - Kimera::Status::KILLING))
      for_all(results, options, bad, runs: 300) do |outcomes, options, extra|
        next unless status(outcomes, options) == 2
        expect(status(outcomes + [extra], options)).to(eq(2), "#{extra} turned the gate green")
      end
    end

    # Outcomes, gate settings, and the status they must give.
    def thresholds
      [
        [[:killed], {}, 0], [[:survived], {}, 2],
        [[:survived], { max_survivors: 1 }, 0], [%i[survived survived], { max_survivors: 1 }, 2],
        [[:ignored] * 2, { max_ignored: 2 }, 0], [[:ignored] * 3, { max_ignored: 2 }, 2],
        [[:ignored] * 9, {}, 0], [[:harness_error], {}, 2],
        [[:harness_error], { max_errors: 1 }, 0], [[:harness_error] * 2, { max_errors: 1 }, 2],
        [[:no_coverage], {}, 0], [[:no_coverage], { fail_on_no_coverage: true }, 2],
        [[:no_coverage], { count_no_coverage: true }, 2],
        [[:isolated_only], {}, 2], [%i[isolated_only killed], {}, 0],
        [%i[isolated_only survived], { max_survivors: 1 }, 2]
      ]
    end

    it "passes at each threshold and fails one past it" do
      expect(thresholds.reject { |outcomes, options, wanted| status(outcomes, options) == wanted }).to(be_empty)
    end
  end

  describe Kimera::Report::Tally do
    # The width of the bar drawn after each tick.
    def widths(total, ticks)
      tally = described_class.new(total, "mutants", 0.0)
      ticks.first(total).each_with_index.map do |status, i|
        tally.count!(status)
        tally.line(i + 1.5)[/\[[^\]]*\]/].size
      end
    end

    it "draws a bar of fixed width at every point of a run" do
      for_all(Pbt.integer(min: 1, max: 5000), Pbt.array(statuses, max: 60), runs: 300) do |total, ticks|
        expect(widths(total, ticks).uniq - [described_class::BAR_WIDTH + 2]).to(be_empty)
      end
    end
  end
end
