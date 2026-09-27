# frozen_string_literal: true

require_relative "../flag"

module Kimera
end

class Kimera::CLI
end

module Kimera::CLI::RunOptions
  DEFAULT_TESTS = ["spec/**/*_spec.rb"].freeze

  OPTIONS = Kimera::FlagTable.new(
    banner: "Usage: kimera run [paths...] [options]\n" \
      "Exit codes: 0 gates passed, 1 usage or setup error, 2 gate failed",
    flags: [
      Kimera::Flag.build("--framework NAME", :framework, "Test framework (rspec)"),
      Kimera::Flag.build(
        "--tests GLOB", :cli_tests,
        "Test file glob (repeatable; replaces config tests:)", collect: true
      ),
      Kimera::Flag.build("--source-root DIR", :source_root, "Project root for synthesis"),
      Kimera::REGISTRY_FLAG,
      Kimera::OPERATORS_FLAG,
      Kimera::REQUIRE_FLAG,
      Kimera::Flag.build(
        "--soft-timeout SEC", :soft_timeout, "Soft timeout for a mutant's covering tests", type: Float
      ),
      Kimera::Flag.build(
        "--hard-timeout SEC", :hard_timeout, "Watchdog kill timeout per mutant and per baseline test", type: Float
      ),
      Kimera::Flag.build("--leak-every N", :leak_every, "Re-check a killed mutant every N", type: Integer),
      Kimera::Flag.build("--[no-]coverage", :coverage, "Run each mutant only against covering tests (default: on)"),
      Kimera::Flag.build("--since REF", :since, "Incremental: only mutate lines changed vs REF (git diff)"),
      Kimera::Flag.build("--session FILE", :session, "Persist/resume per-mutant results in FILE"),
      Kimera::Flag.build(
        "--focus ID", :focus, "Evaluate only one or more mutant IDs (repeatable)",
        type: Integer, collect: true
      ),
      Kimera::Flag.build("--[no-]gate", :gate, "Return gate status (default: on; use --no-gate for exploration)"),
      Kimera::Flag.build("--max-survivors N", :max_survivors, "Gate: fail only if survivors exceed N", type: Integer),
      Kimera::Flag.build(
        "--max-ignored N", :max_ignored,
        "Gate: fail if more than N mutants are ignore-listed", type: Integer
      ),
      Kimera::Flag.build(
        "--evaluate-ignored", :evaluate_ignored,
        "Also run ignored mutants; they stay ignored but record their verdict (killed, survived, ...)"
      ),
      Kimera::Flag.build("--no-baseline", :baseline, "Skip the config's baseline: file (its mutants are judged)"),
      Kimera::Flag.build(
        "--max-errors N", :max_errors,
        "Gate: fail if more than N mutants could not be judged (default 0)", type: Integer
      ),
      Kimera::Flag.build(
        "--[no-]fail-on-no-coverage", :fail_on_no_coverage,
        "Gate: also fail when any mutant in scope has no covering test"
      ),
      Kimera::Flag.build("--jobs N", :jobs, "Concurrent workers (warm pool / isolated mirrors)", type: Integer),
      Kimera::Flag.build(
        "--[no-]progress", :progress, "Live progress bar on stderr (default: on when stderr is a tty)"
      ),
      Kimera::Flag.build(
        "--[no-]color", :color,
        "Color text output (default: on when stdout is a tty; respects NO_COLOR)"
      ),
      Kimera::Flag.build(["-q", "--quiet"], :quiet, "Suppress the final human-readable report"),
      Kimera::Flag.build(["-v", "--verbose"], :verbose, "Print resolved scope and execution settings"),
      Kimera::Flag.build("--log FILE", :log, "Write the final human-readable report to FILE"),
      Kimera::Flag.build(
        "--[no-]isolate-db", :isolate_db, "Wrap each mutant in a rolled-back ActiveRecord transaction"
      ),
      Kimera::Flag.build(
        "--isolated", :isolated,
        "Evaluate every mutant in a fresh subprocess (slow, but trustworthy for " \
          "the runtime selector and harness-critical code)"
      ),
      Kimera::Flag.build(
        "--isolate-when-covered-by SUBSTR", :isolate_when_covered_by,
        "Isolate only mutants whose covering set includes a test id matching SUBSTR " \
          "(repeatable) — a fast, targeted alternative to --isolated for pool-unsafe specs",
        collect: true
      ),
      Kimera::Flag.build("--exclude GLOB", :exclude, "Exclude matching files (repeatable)", collect: true),
      Kimera::Flag.build(
        "--exclude-test GLOB", :exclude_tests, "Exclude matching test files (repeatable)", collect: true
      ),
      Kimera::CONFIG_FLAG,
      Kimera::Flag.build("--report FILE", :report, "Write the canonical JSON report to FILE"),
      Kimera::Flag.build("--format NAME", :format, "Output: text, json, ndjson, github, or sarif (default: text)")
    ]
  )
end
