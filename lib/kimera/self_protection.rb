# frozen_string_literal: true

require_relative "runtime"

module Kimera
  class SelfProtection
    OUT_OF_PROCESS_ENTRYPOINTS = %w[
      execution/isolated_child.rb
      execution/isolated_child_minitest.rb
    ].map { |path| File.expand_path(path, __dir__) }.freeze

    RUNTIME_PATH = File.expand_path("runtime.rb", File.dirname(File.expand_path(__FILE__)))

    PATHS = [RUNTIME_PATH, *OUT_OF_PROCESS_ENTRYPOINTS].freeze

    HOME = File.dirname(RUNTIME_PATH)

    HARNESS_CRITICAL_SUFFIXES = %w[
      kimera/frameworks/suite.rb
      kimera/frameworks/rspec_suite.rb
      kimera/frameworks/suite_registry.rb
      kimera/frameworks/group_scope.rb
      kimera/frameworks/group_tree.rb
      kimera/frameworks/minitest_suite.rb
      kimera/exits/test_exit.rb
      kimera/frameworks/class_hooks.rb
      kimera/execution/shift.rb
      kimera/execution/shift/attempt.rb
      kimera/execution/shift/deadline.rb
      kimera/execution/shift/overrun.rb
      kimera/execution/shift/expiry.rb
      kimera/execution/shift/stall.rb
      kimera/execution/shift/lapse.rb
      kimera/execution/shift/subject.rb
      kimera/execution/shift/suspect.rb
      kimera/execution/shift/doubt.rb
      kimera/execution/shift/lag.rb
      kimera/execution/shift/kill.rb
      kimera/execution/shift/lineup.rb
      kimera/execution/shift/interruption.rb
      kimera/execution/shift/probe.rb
      kimera/execution/shift/finding.rb
      kimera/execution/shift/failure.rb
      kimera/execution/shift/hang.rb
      kimera/execution/shift/slowdown.rb
      kimera/execution/shift/inconclusive.rb
      kimera/execution/shift/coverage_channel.rb
      kimera/execution/shift/killer_memory.rb
      kimera/execution/shift/unmask.rb
      kimera/execution/pace.rb
      kimera/execution/zygote.rb
      kimera/execution/harness.rb
      kimera/execution/baseline_pass.rb
      kimera/execution/baseline_tally.rb
      kimera/execution/stopwatch.rb
      kimera/execution/time_budget.rb
      kimera/execution/patience.rb
      kimera/execution/reload.rb
      kimera/execution/overlaying.rb
      kimera/execution/worker_databases.rb
      kimera/execution/verdicts.rb
      kimera/execution/triage.rb
      kimera/execution/worker_pool.rb
      kimera/execution/worker_pool/fleet.rb
      kimera/execution/child_process.rb
      kimera/execution/rig.rb
      kimera/registry/builder.rb
    ].freeze

    def initialize(path)
      @path = path
    end

    def critical?
      text = @path.to_s
      HARNESS_CRITICAL_SUFFIXES.any? { |suffix| text.end_with?(suffix) }
    end

    def protected?
      target = canonical(@path)
      PATHS.any? { |own| canonical(own) == target }
    end

    def own? = canonical(@path).start_with?("#{canonical(HOME)}/")

    private

    def canonical(path)
      File.realpath(path)
    rescue SystemCallError
      File.expand_path(path)
    end
  end
end
