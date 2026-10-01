# frozen_string_literal: true

require_relative "isolated_outcome"

module Kimera
  module Execution
    module IsolatedVerdict
      private

      def evaluate(trial)
        point = plan.registry.index[trial.id]
        return error(trial, "unknown mutant") unless point
        bake(trial, point)
      rescue StandardError => error
        self.error(trial, "#{error.class}: #{error.message}")
      end

      def single(id)
        result = with_mirror { |mirror| evaluate(Kimera::Execution::Trial.new(id, mirror, Overlay.new(plan.registry))) }
        return unstaged(result) if result.status == :error
        result.killed? ? confirmed(result) : result
      end

      def unstaged(result)
        result.unjudged("the isolated tier could not stage it: #{result.detail}")
      end

      def confirmed(result)
        control = with_mirror { |mirror| verdict(mirror, result.covering_tests) }
        return result if control.status == :survived
        result.unjudged("its tests fail in a fresh mirror without the mutant too (#{control.explain(limit)})")
      end

      def bake(trial, point)
        trial.file = point.file
        tests = plan.tests(trial.id, point)
        return result(trial, status: :no_coverage) unless tests
        outcome, duration = measure(trial, tests)
        result(
          trial,
          status: outcome.status, duration: duration, covering_tests: tests, failing_tests: outcome.failing,
          detail: outcome.detail
        )
      end

      def measure(trial, tests)
        started = now
        [with_mutant(trial) { verdict(trial.mirror, tests) }, now - started]
      rescue Kimera::Overlay::Unbakeable => error
        [IsolatedOutcome.new(:unmutatable, nil, "#{Kimera::MutationPoint::UNMUTATABLE}#{error.message}"), nil]
      end

      def with_mutant(trial)
        original, target = trial.stage(plan.root)
        yield
      ensure
        File.write(target, original) if original
      end

      def verdict(mirror, locations)
        Dir.mktmpdir("kimera-ledger") do |dir|
          ledger = File.join(dir, "ledger.json")
          stderr = File.join(dir, "stderr.log")
          IsolatedOutcome::Ruling.new(launch(mirror, locations, ledger, stderr), ledger, captured(stderr)).outcome
        end
      end

      def captured(path) = File.read(path, encoding: Encoding::UTF_8).scrub

      def launch(mirror, locations, ledger, stderr)
        env, cmd = plan.command(mirror, locations, ledger)
        pulse = "#{ledger}#{Kimera::Execution::IsolatedPlan::ChildCommand::PULSE}"
        waitfor(Process.spawn(env, *cmd, chdir: mirror, pgroup: true, out: File::NULL, err: stderr), pulse)
      end

      def with_mirror
        Dir.mktmpdir("kimera-isolated") do |mirror|
          populate(mirror)
          yield(mirror)
        end
      end

      def populate(mirror)
        root = plan.root
        Dir.children(root).each { |entry| place(File.join(root, entry), File.join(mirror, entry), entry) }
      end

      def place(source, target, entry)
        case plan.placement(entry)
        when :copy then FileUtils.cp_r(source, target)
        when :link then File.symlink(source, target)
        when :empty then FileUtils.mkdir_p(target) if File.directory?(source)
        end
      end

      def result(trial, **outcome) = MutantResult.new(mutant_id: trial.id, file: trial.file, **outcome)

      def error(trial, detail) = result(trial, status: :error, detail: detail)

      def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
