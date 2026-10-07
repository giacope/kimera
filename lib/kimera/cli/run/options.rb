# frozen_string_literal: true

require_relative "../flag"
require_relative "../report_file"
require_relative "flags"

module Kimera
end

class Kimera::CLI
end

module Kimera::CLI::RunOptions
  DEFAULT_TESTS = ["spec/**/*_spec.rb"].freeze

  GATES = [
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
    )
  ].freeze

  OUTPUT = [
    Kimera::Flag.build(
      "--[no-]progress", :progress,
      "Progress on stderr: a live bar on a tty, else plain lines every 30s (default: on)"
    ),
    Kimera::Flag.build(
      "--[no-]color", :color,
      "Color text output (default: on when stdout is a tty; respects NO_COLOR)"
    ),
    Kimera::Flag.build(["-q", "--quiet"], :quiet, "Suppress the final human-readable report"),
    Kimera::Flag.build(["-v", "--verbose"], :verbose, "Print resolved scope and execution settings"),
    Kimera::Flag.build("--log FILE", :log, "Write the final human-readable report to FILE"),
    Kimera::Flag.build("--pidfile FILE", :pidfile, "Write kimera's process id to FILE, removed when the run ends"),
    Kimera::Flag.build(
      "--report FILE", :report, "Write the canonical JSON report to FILE (default: #{Kimera::CLI::ReportFile::DEFAULT})"
    ),
    Kimera::Flag.build("--no-report", :report, "Write no JSON report"),
    Kimera::Flag.build("--format NAME", :format, "Output: text, json, ndjson, github, or sarif (default: text)")
  ].freeze

  OPTIONS = Kimera::FlagTable.new(
    banner: "Usage: kimera run [paths...] [options]\n" \
      "Paths take an optional line or range: app/models/order.rb:42 or app/models/order.rb:40-60\n" \
      "Exit codes: 0 gates passed, 1 usage or setup error, 2 gate failed",
    flags: Kimera::CLI::RunFlags::SCOPE + Kimera::CLI::RunFlags::EXECUTION + GATES + OUTPUT
  )
end
