# frozen_string_literal: true

module KimeraEval
  # H1: an external holdout. Twelve projects that leak state between tests
  # in different ways, written by another agent blind to kimera's sources,
  # tests and this eval, with that agent's own oracle (eval/holdout/README.md).
  # Each runs under `kimera run --operators all --jobs 2`; the holdout oracle
  # bakes every reported mutant into a copy and runs plain rspec in a new
  # process. A false no_coverage is a mutant kimera calls uncovered that the
  # plain suite kills.
  class HoldoutCase < Case
    ID = "H1"
    TITLE = "External holdout: 12 state-leak projects and an oracle written blind to kimera"
    HOLDOUT = File.join(ROOT, "eval", "holdout")
    ARGS = %w[run --operators all --jobs 2 --no-progress].freeze
    WRONG = %w[false_survived false_killed false_no_coverage errors].freeze
    COUNTED = %w[mutants compared agree skipped false_survived false_killed no_coverage false_no_coverage].freeze

    def call
      runs = Dir[File.join(HOLDOUT, "p*")].to_h { |dir| [File.basename(dir), judged(dir)] }
      total = sum(runs.values)
      { "pass" => total.values_at(*WRONG).sum.zero?, "summary" => summary(total) }
        .merge("totals" => total).merge("projects" => runs)
    end

    private

    def judged(dir)
      copy = sandbox.copy(dir)
      report = File.join(sandbox.root, "#{File.basename(dir)}.json")
      result = checkout.cli(*ARGS, "--report", report, chdir: copy)
      File.exist?(report) ? scored(copy, report) : { "error" => "no report (exit #{result.code})" }
    end

    def scored(copy, report)
      out = "#{report}.oracle.json"
      Shell.new(chdir: HOLDOUT, timeout: 1800).run("ruby", "oracle.rb", copy, report, "--json", out, "--jobs", "4")
      File.exist?(out) ? counts(JSON.parse(File.read(out))) : { "error" => "the holdout oracle found the suite red" }
    end

    def counts(found)
      found.slice("compared", "agree").merge("mutants" => found["total"], "skipped" => found["skipped"].size)
        .merge("false_survived" => found["false_survivors"].size, "false_killed" => found["false_kills"].size)
        .merge(uncovered(found.fetch("records")))
    end

    def uncovered(records)
      found = records.select { |record| record["tool"] == "no_coverage" }
      { "no_coverage" => found.size, "false_no_coverage" => found.count { |row| row["oracle"] == "killed" } }
    end

    def sum(runs)
      COUNTED.to_h { |key| [key, runs.sum { |run| run.fetch(key, 0) }] }
        .merge("errors" => runs.count { |run| run["error"] })
    end

    def summary(total)
      compared = total["compared"]
      agreement = compared.zero? ? nil : (100.0 * total["agree"] / compared).round(1)
      total.slice("mutants", "compared", *WRONG).merge("agreement_pct" => agreement)
    end
  end
end
