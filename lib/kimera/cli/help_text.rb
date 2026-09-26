# frozen_string_literal: true

require_relative "../scope/file_set"
require_relative "../version"

module Kimera
  module HelpText
    HELP = <<~HELP.freeze
      kimera #{Kimera::VERSION} -- schemata-based mutation testing for Ruby
      (every mutant is compiled into one guarded source tree, so the suite
      loads once, not once per mutant)

      Usage: kimera <command> [options]

      Start here:
        init                  Detect this project and create .kimera.yml
        doctor                Validate source/test discovery and runtime safety
        run [paths...]        Run mutation tests locally
        changed [paths...]    Mutate only code changed since origin/main (or main)
        ci [paths...]         Strict CI gate; writes a report artifact

      Investigate:
        report REPORT.json    Filter a saved report (survivors, uncovered, errors)
        mutant ID --report R  Show one mutant in full detail
        registry [paths...]   Inspect what Kimera would mutate
        synthesize [paths...] Write schemata sources for inspection

      Setup:
        baseline ...          Create or review a baseline of accepted survivors
        completion SHELL      Print Bash, Zsh, or Fish completion setup
        skill                 Print the guide for AI agents running Kimera
        version               Print version
        help                  Show this help

      With no paths, defaults to: #{Kimera::FileSet::DEFAULT_GLOBS.join(", ")}

      Exit codes: 0 ok, 1 usage or setup error, 2 gate failed (run)

      Examples:
        kimera init && kimera doctor
        kimera changed --report tmp/kimera/report.json
        kimera report tmp/kimera/report.json --status no_coverage
    HELP
  end
end
