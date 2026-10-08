# frozen_string_literal: true

require_relative "../flag"

module Kimera
end

class Kimera::CLI
end

module Kimera::CLI::RunFlags
  SCOPE = [
    Kimera::Flag.build("--framework NAME", :framework, "Test framework (rspec)"),
    Kimera::Flag.build(
      "--tests GLOB", :cli_tests,
      "Test file glob (repeatable; replaces config tests:)", collect: true
    ),
    Kimera::Flag.build("--source-root DIR", :source_root, "Project root for synthesis"),
    Kimera::REGISTRY_FLAG,
    Kimera::OPERATORS_FLAG,
    Kimera::REQUIRE_FLAG,
    Kimera::Flag.build("--since REF", :since, "Incremental: only mutate lines changed vs REF (git diff)"),
    Kimera::Flag.build("--session FILE", :session, "Persist/resume per-mutant results in FILE"),
    Kimera::Flag.build(
      "--focus ID|KEY", :focus, "Evaluate only these mutants, by ID or report key (repeatable)",
      collect: true
    ),
    Kimera::Flag.build(
      "--method NAME", :methods, "Only mutate inside methods named NAME (repeatable)", collect: true
    ),
    Kimera::Flag.build("--exclude GLOB", :exclude, "Exclude matching files (repeatable)", collect: true),
    Kimera::Flag.build(
      "--exclude-test GLOB", :exclude_tests, "Exclude matching test files (repeatable)", collect: true
    ),
    Kimera::CONFIG_FLAG
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
    Kimera::Flag.build("--leak-every N", :leak_every, "Re-check a killed mutant every N", type: Integer),
    Kimera::Flag.build("--[no-]coverage", :coverage, "Run each mutant only against covering tests (default: on)"),
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
      "--isolate-when-covered-by SUBSTR", :isolate_when_covered_by,
      "Isolate only mutants whose covering set includes a test id matching SUBSTR " \
        "(repeatable) — a fast, targeted alternative to --isolated for pool-unsafe specs",
      collect: true
    )
  ].freeze
end
