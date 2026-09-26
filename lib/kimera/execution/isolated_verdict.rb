# frozen_string_literal: true

module Kimera
  module Execution
    module IsolatedExecutionVerdict
      private

      def evaluate(trial)
        point = plan.registry.index[trial.id]
        return error(trial, "unknown mutant") unless point
        bake(trial, point)
      rescue StandardError => error
        self.error(trial, "#{error.class}: #{error.message}")
      end

      def bake(trial, point)
        trial.file = point.file
        tests = plan.tests(trial.id, point)
        return result(trial, :no_coverage, nil) unless tests
        status, duration = measure(trial, tests)
        result(trial, status, duration, tests)
      end

      def measure(trial, tests)
        started = now
        [with_mutant(trial) { verdict(trial.mirror, tests) }, now - started]
      end

      def with_mutant(trial)
        original, target = trial.stage(plan.root)
        yield
      ensure
        File.write(target, original) if original
      end

      def verdict(mirror, locations)
        env, cmd = plan.command(mirror, locations)
        status = waitfor(Process.spawn(env, *cmd, chdir: mirror, pgroup: true, out: File::NULL, err: File::NULL))
        return :timeout if status == :timeout
        status.success? ? :survived : :killed
      end

      def with_mirror
        Dir.mktmpdir("kimera-isolated") do |mirror|
          populate(mirror)
          yield(mirror)
        end
      end

      def populate(mirror)
        root = plan.root
        IsolatedPlan.mirrors(Dir.children(root)).each do |entry|
          FileUtils.cp_r(File.join(root, entry), File.join(mirror, entry))
        end
      end

      def result(trial, status, duration, cover = nil)
        MutantResult.new(
          mutant_id: trial.id, status: status, file: trial.file, duration: duration, covering_tests: cover
        )
      end

      def error(trial, detail)
        MutantResult.new(mutant_id: trial.id, status: :error, file: trial.file, detail: detail)
      end

      def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
