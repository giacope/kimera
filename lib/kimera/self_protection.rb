# frozen_string_literal: true

require_relative "runtime"

module Kimera
  module SelfProtection
    module_function

    OUT_OF_PROCESS_ENTRYPOINTS = %w[
      execution/isolated_child.rb
      execution/isolated_child_minitest.rb
    ].map { |path| File.expand_path(path, __dir__) }.freeze

    def paths
      [Runtime::SOURCE_PATH, *OUT_OF_PROCESS_ENTRYPOINTS]
    end

    HARNESS_CRITICAL_SUFFIXES = %w[
      kimera/frameworks/adapter.rb
      kimera/frameworks/rspec_adapter.rb
      kimera/frameworks/adapter_registry.rb
      kimera/frameworks/group_scope.rb
      kimera/frameworks/group_tree.rb
      kimera/frameworks/minitest_adapter.rb
      kimera/support/test_exit.rb
      kimera/execution/shift.rb
      kimera/execution/shift/attempt.rb
      kimera/execution/shift/deadline.rb
      kimera/execution/shift/overrun.rb
      kimera/execution/shift/subject.rb
      kimera/execution/shift/suspect.rb
      kimera/execution/shift/trial.rb
      kimera/execution/shift/coverage_channel.rb
      kimera/execution/shift/killer_memory.rb
      kimera/execution/shift/leak_guard.rb
      kimera/execution/harness.rb
      kimera/execution/baseline_pass.rb
      kimera/execution/baseline_tally.rb
      kimera/execution/stopwatch.rb
      kimera/execution/time_budget.rb
      kimera/execution/reload.rb
      kimera/execution/worker_databases.rb
      kimera/execution/verdicts.rb
      kimera/execution/worker_pool.rb
      kimera/execution/worker_pool/fleet.rb
      kimera/execution/child_process.rb
      kimera/execution/rig.rb
      kimera/registry/builder.rb
    ].freeze

    def critical?(path)
      text = path.to_s
      HARNESS_CRITICAL_SUFFIXES.any? { |suffix| text.end_with?(suffix) }
    end

    def protected?(path)
      target = canonical(path)
      paths.any? { |own| canonical(own) == target }
    end

    def canonical(path)
      File.realpath(path)
    rescue SystemCallError
      File.expand_path(path)
    end
  end
end
