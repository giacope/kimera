# frozen_string_literal: true

require_relative "../flag"

module Kimera
end

class Kimera::CLI
end

module Kimera::CLI::RunOptions
  SCOPE = [
    Kimera::Flag.build("--framework NAME", :framework, "Test framework (rspec)"),
    Kimera::Flag.repeated("--tests GLOB", :cli_tests, "Test file glob (repeatable; replaces config tests:)"),
    Kimera::Flag.build("--source-root DIR", :source_root, "Project root for synthesis"),
    Kimera::Flag.shared(:registry),
    Kimera::Flag.shared(:operators),
    Kimera::Flag.shared(:require),
    Kimera::Flag.build("--since REF", :since, "Incremental: mutate what changed vs REF (git diff; see --since-scope)"),
    Kimera::Flag.build(
      "--since-scope SCOPE", :since_scope,
      "What --since mutates: every line of each changed file (files, the default), those files and the files " \
        "the changed tests reach in the stored coverage map (impact), or only the changed lines (lines)"
    ),
    Kimera::Flag.build("--session FILE", :session, "Persist/resume per-mutant results in FILE"),
    Kimera::Flag.repeated("--focus ID|KEY", :focus, "Evaluate only these mutants, by ID or report key (repeatable)"),
    Kimera::Flag.repeated("--method NAME", :methods, "Only mutate inside methods named NAME (repeatable)"),
    Kimera::Flag.repeated("--exclude GLOB", :exclude, "Exclude matching files (repeatable)"),
    Kimera::Flag.repeated("--exclude-test GLOB", :exclude_tests, "Exclude matching test files (repeatable)"),
    Kimera::Flag.repeated(
      "--exclude-test-name REGEX", :exclude_test_names,
      "Leave out the tests whose name or id matches REGEX, keeping the rest of their file (repeatable)"
    ),
    Kimera::Flag.shared(:config)
  ].freeze

  EXECUTION = [
    Kimera::Flag.build(
      "--soft-timeout SEC", :soft_timeout, "Soft timeout for each covering test a mutant runs", type: Float
    ),
    Kimera::Flag.build(
      "--hard-timeout SEC", :hard_timeout, "Watchdog kill timeout per test (per mutant in --isolated)", type: Float
    ),
    Kimera::Flag.build(
      "--[no-]relative-timeout", :relative_timeout,
      "A warm covering test past its baseline time x factor + slack is a timeout (default: on)"
    ),
    Kimera::Flag.build(
      "--timeout-factor N", :timeout_factor, "Relative timeout: multiple of the test's baseline time (default 10)",
      type: Float
    ),
    Kimera::Flag.build(
      "--timeout-slack SEC", :timeout_slack, "Relative timeout: seconds added to the multiple (default 1)",
      type: Float
    ),
    Kimera::Flag.build("--[no-]coverage", :coverage, "Run each mutant only against covering tests (default: on)"),
    Kimera::Flag.build(
      "--[no-]reuse-coverage", :reuse_coverage,
      "Keep a full run's coverage map; --since then reruns only the tests it says reach changed code (default: off)"
    ),
    Kimera::Flag.build("--jobs N", :jobs, "Concurrent workers (warm pool / isolated mirrors)", type: Integer),
    Kimera::Flag.build(
      "--[no-]isolate-db", :isolate_db, "Wrap each mutant in a rolled-back ActiveRecord transaction"
    ),
    Kimera::Flag.build(
      "--isolated", :isolated,
      "Evaluate every mutant in a fresh subprocess (slow, but trustworthy for " \
        "the runtime selector and harness-critical code)"
    ),
    Kimera::Flag.build(
      "--[no-]rejudge", :rejudge,
      "Judge again, each in a fresh isolated mirror, the mutants the warm pass could not judge (default: on)"
    ),
    Kimera::Flag.build(
      "--attribution MODE", :attribution,
      "Which covering tests may kill a mutant: any (default) or unit (only its own file's tests)"
    ),
    Kimera::Flag.repeated(
      "--unit-tests GLOB=PATTERN", :cli_unit_tests,
      "Strict attribution: tests matching PATTERN ({path}, {name}) are the own tests of sources " \
        "matching GLOB, beside the usual layouts (repeatable; replaces config unit_tests:)"
    ),
    Kimera::Flag.build(
      "--seed N|random", :seed,
      "Seed each test's random numbers (and Minitest's order) with N, or a random N the report records"
    ),
    Kimera::Flag.build(
      "--flaky-runs N", :flaky_runs,
      "Rerun the covering tests N more times, each with another seed; a test whose result changes is " \
        "flaky, reported, and never kills (default: 0)",
      type: Integer
    ),
    Kimera::Flag.build(
      "--[no-]test-quality", :test_quality,
      "Record every test that kills each mutant, and report tests that kill nothing or only what " \
        "others kill (nightly; default: off)"
    ),
    Kimera::Flag.repeated(
      "--isolate-when-covered-by SUBSTR", :isolate_when_covered_by,
      "Isolate only mutants whose covering set includes a test id matching SUBSTR " \
        "(repeatable) — a fast, targeted alternative to --isolated for pool-unsafe specs"
    )
  ].freeze
  private_constant(:SCOPE, :EXECUTION)
end
