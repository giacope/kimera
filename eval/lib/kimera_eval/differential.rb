# frozen_string_literal: true

require "json"

module KimeraEval
  # Runs kimera on a project and compares each verdict with the oracle's.
  #
  # Agreement: killed/timeout/error vs killed; survived or no_coverage vs
  # survived. A survived or no_coverage verdict the oracle kills is a false
  # survivor; a kill the oracle doesn't confirm is a false kill. Statuses
  # that judge nothing (harness_error, isolated_only, unmutatable, ignored)
  # are abstentions, counted apart.
  class Differential
    KILLS = %w[killed timeout error].freeze
    SURVIVALS = %w[survived no_coverage].freeze
    VERDICTS = %w[agree false_survived false_killed abstained unbakeable].freeze

    Target = Data.define(:project, :args, :env)

    def initialize(checkout, target, oracle:)
      @checkout = checkout
      @target = target
      @oracle = oracle
    end

    def call(mode)
      report = File.join(@target.project, "tmp", "eval-#{mode.join.delete("-")}.json")
      arguments = ["run", *@target.args, *mode, "--report", report, "--no-progress"]
      run = @checkout.cli(*arguments, chdir: @target.project, env: @target.env)
      return failed(run, mode) unless File.exist?(report)
      compare(JSON.parse(File.read(report, encoding: Encoding::UTF_8)), run)
    end

    private

    def failed(run, mode)
      { "mode" => mode.join(" "), "error" => "no report (exit #{run.code}): #{run.output.lines.last(8).join}" }
    end

    def compare(report, run)
      results = report.fetch("results")
      truth = @oracle.verdicts(bake(results.map { |result| result["mutant_id"] }))
      summary(results.map { |result| row(result, truth.fetch(result["mutant_id"].to_s)) }, run).merge(notes(report))
    end

    def notes(report)
      { "leaks" => Array(report["leaks"]).size, "rejudged" => report.fetch("results").count { |row| row["note"] } }
    end

    def bake(ids)
      script = File.join(__dir__, "bake.rb")
      JSON.parse(@checkout.script(script, *@target.args, chdir: @target.project, stdin: JSON.generate(ids)).stdout)
    end

    def row(result, oracle)
      result.slice("file", "line", "label").merge("id" => result["mutant_id"], "kimera" => result["status"])
        .merge("oracle" => oracle, "verdict" => judge(result["status"], oracle))
    end

    def judge(status, oracle)
      return "unbakeable" if oracle == "unbakeable"
      return "abstained" unless KILLS.include?(status) || SURVIVALS.include?(status)
      return "agree" if KILLS.include?(status) == (oracle == "killed")
      KILLS.include?(status) ? "false_killed" : "false_survived"
    end

    def summary(rows, run)
      tally = rows.map { |row| row["verdict"] }.tally
      counts(tally, rows.size).merge("agreement_pct" => Scoring.agreement(tally)).merge(measured(run))
        .merge("statuses" => rows.map { |row| row["kimera"] }.tally)
        .merge("disagreements" => rows.reject { |row| row["verdict"] == "agree" })
    end

    def measured(run) = { "wall_s" => run.wall.round(2), "exit" => run.code, "rss" => run.rss }

    def counts(tally, total)
      { "mutants" => total }.merge(VERDICTS.to_h { |verdict| [verdict, tally.fetch(verdict, 0)] })
    end
  end

  # Agreement over the mutants both sides judged.
  module Scoring
    module_function

    def agreement(tally)
      judged = tally.sum { |verdict, count| %w[abstained unbakeable].include?(verdict) ? 0 : count }
      judged.zero? ? nil : (100.0 * tally.fetch("agree", 0) / judged).round(1)
    end
  end
end
