# frozen_string_literal: true

require "json"

module KimeraEval
  class Differential
    KILLS = %w[killed timeout error].freeze
    SURVIVALS = %w[survived no_coverage].freeze
    VERDICTS = %w[agree false_survived false_killed abstained unbakeable].freeze

    class Target
      def initialize(project, arguments, env)
        @project = project
        @arguments = arguments
        @env = env
      end

      def ran(checkout, mode)
        report = File.join(@project, "tmp", "eval-#{mode.join.delete("-")}.json")
        arguments = ["run", *@arguments, *mode, "--report", report, "--no-progress"]
        [report, *checkout.cli(*arguments, chdir: @project, env: @env)]
      end

      def baked(checkout, script, ids)
        _, printed = checkout.script(script, *@arguments, chdir: @project, stdin: JSON.generate(ids))
        JSON.parse(printed.to_s)
      end

      def copied(sandbox) = self.class.new(sandbox.copy(@project), @arguments, @env)
    end

    def initialize(checkout, target, oracle:)
      @checkout = checkout
      @target = target
      @oracle = oracle
    end

    def call(mode)
      report, *run = @target.ran(@checkout, mode)
      return failed(*run, mode) unless File.exist?(report)
      compare(JSON.parse(File.read(report, encoding: Encoding::UTF_8)), *run)
    end

    private

    def failed(exit, printed, _usage, mode)
      { "mode" => mode.join(" "), "error" => "#{exit.unreported}: #{printed.output.lines.last(8).join}" }
    end

    def compare(report, exit, _printed, usage)
      results = report.fetch("results")
      truth = @oracle.verdicts(bake(results.map { |result| result["mutant_id"] }))
      summary(results.map { |result| row(result, truth.fetch(result["mutant_id"].to_s)) }, exit, usage)
        .merge(notes(report))
    end

    def notes(report)
      { "leaks" => Array(report["leaks"]).size, "rejudged" => report.fetch("results").count { |row| row["note"] } }
    end

    def bake(ids) = @target.baked(@checkout, File.join(__dir__, "bake.rb"), ids)

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

    def summary(rows, exit, usage)
      counts(rows.map { |row| row["verdict"] }.tally, rows.size).merge(measured(exit, usage))
        .merge("statuses" => rows.map { |row| row["kimera"] }.tally)
        .merge("disagreements" => rows.reject { |row| row["verdict"] == "agree" })
    end

    def measured(exit, usage) = usage.timed(2).merge(exit.exited).merge("rss" => usage.to_h)

    def counts(tally, total)
      { "mutants" => total }.merge(VERDICTS.to_h { |verdict| [verdict, tally.fetch(verdict, 0)] })
        .merge(Agreement.new(tally).to_h)
    end

    class Agreement
      def initialize(tally)
        @tally = tally
      end

      def to_h
        judged = verdicts.sum { |verdict, count| %w[abstained unbakeable].include?(verdict) ? 0 : count }
        { "agreement_pct" => judged.zero? ? nil : (100.0 * verdicts.fetch("agree", 0) / judged).round(1) }
      end

      private

      def verdicts = @tally.slice(*VERDICTS)
    end
  end
end
