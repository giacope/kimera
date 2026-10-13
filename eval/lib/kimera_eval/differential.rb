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

    def initialize(checkout, project, oracle:, args: [], env: {})
      @checkout = checkout
      @project = project
      @oracle = oracle
      @args = args
      @env = env
    end

    def call(mode)
      report = File.join(@project, "tmp", "eval-#{mode.join("-").delete("-")}.json")
      run = @checkout.kimera("run", *@args, *mode, "--report", report, "--no-progress", chdir: @project, env: @env)
      return failed(run, mode) unless File.exist?(report)
      compare(JSON.parse(File.read(report, encoding: Encoding::UTF_8)), run).merge("rss" => run.rss)
    end

    private

    def failed(run, mode)
      { "mode" => mode.join(" "), "error" => "no report (exit #{run.code}): #{run.output.lines.last(8).join}" }
    end

    def compare(report, run)
      results = report.fetch("results")
      truth = @oracle.verdicts(bake(results.map { |result| result["mutant_id"] }))
      rows = results.map { |result| row(result, truth.fetch(result["mutant_id"].to_s)) }
      summary(rows, run).merge("leaks" => Array(report["leaks"]).size, "rejudged" => results.count { |result| result["note"] })
    end

    def bake(ids)
      script = File.join(__dir__, "bake.rb")
      out = @checkout.ruby(script, *@args, chdir: @project, stdin: JSON.generate(ids))
      JSON.parse(out.out)
    end

    def row(result, oracle)
      { "id" => result["mutant_id"], "file" => result["file"], "line" => result["line"], "label" => result["label"] }
        .merge("kimera" => result["status"], "oracle" => oracle, "verdict" => judge(result["status"], oracle))
    end

    def judge(status, oracle)
      return "unbakeable" if oracle == "unbakeable"
      return "abstained" unless KILLS.include?(status) || SURVIVALS.include?(status)
      return "agree" if KILLS.include?(status) == (oracle == "killed")
      KILLS.include?(status) ? "false_killed" : "false_survived"
    end

    def summary(rows, run)
      tally = rows.map { |row| row["verdict"] }.tally
      judged = rows.size - tally.fetch("abstained", 0) - tally.fetch("unbakeable", 0)
      counts(tally, rows.size).merge(
        "agreement_pct" => judged.zero? ? nil : (100.0 * tally.fetch("agree", 0) / judged).round(1),
        "wall_s" => run.wall.round(2), "exit" => run.code, "statuses" => rows.map { |row| row["kimera"] }.tally,
        "disagreements" => rows.reject { |row| row["verdict"] == "agree" }
      )
    end

    def counts(tally, total)
      { "mutants" => total, "agree" => tally.fetch("agree", 0), "false_survived" => tally.fetch("false_survived", 0) }
        .merge("false_killed" => tally.fetch("false_killed", 0), "abstained" => tally.fetch("abstained", 0))
        .merge("unbakeable" => tally.fetch("unbakeable", 0))
    end
  end
end
