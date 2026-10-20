# frozen_string_literal: true

require_relative "isolated_outcome"
require_relative "mirror_git"

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

      def single(id, slot = nil)
        trial = ->(mirror) { Kimera::Execution::Trial.new(id, mirror, Overlay.new(plan.registry), nil, slot) }
        result = with_mirror { |mirror| evaluate(trial.call(mirror)) }
        return unstaged(result) if result.status == :error
        result.killed? ? confirmed(result, slot) : result
      end

      def unstaged(result)
        result.unjudged("the isolated tier could not stage it: #{result.detail}")
      end

      def confirmed(result, slot = nil)
        control = with_mirror { |mirror| verdict(mirror, result.covering_tests, slot: slot) }
        return result if control.status == :survived
        result.unjudged("its tests fail in a fresh mirror without the mutant too (#{control.explain(limit)})")
      end

      def bake(trial, point)
        trial.file = point.file
        settled = plan.settled(trial.id, point)
        return settled if settled
        tests = plan.tests(trial.id, point)
        return result(trial, status: :no_coverage) unless tests
        judged(trial, tests, *measure(trial, tests))
      end

      def judged(trial, tests, outcome, duration)
        result(
          trial,
          status: outcome.status, duration: duration, covering_tests: tests, failing_tests: outcome.failing,
          detail: outcome.detail, killing_tests: outcome.killers(plan.quality?)
        )
      end

      def measure(trial, tests)
        started = now
        [with_mutant(trial) { settle(trial, plan.fastest(tests)) }, now - started]
      rescue Kimera::Overlay::Unbakeable => error
        [IsolatedOutcome.new(:unmutatable, nil, "#{Kimera::MutationPoint::UNMUTATABLE}#{error.message}"), nil]
      end

      def settle(trial, tests)
        outcome = verdict(trial.mirror, tests, first: !plan.quality?, slot: trial.slot)
        return outcome unless outcome.outside?
        again = verdict(trial.mirror, tests, first: !plan.quality?, slot: trial.slot)
        again.outside? ? again.recurred : again
      end

      def with_mutant(trial)
        original, target = trial.stage(plan.root)
        yield
      ensure
        File.write(target, original) if original
      end

      def verdict(mirror, locations, first: false, slot: nil)
        Dir.mktmpdir("kimera-ledger") do |dir|
          ledger = File.join(dir, "ledger.json")
          stderr = File.join(dir, "stderr.log")
          command = plan.command(mirror, locations, ledger, first: first, slot: slot)
          IsolatedOutcome::Ruling.new(launch(mirror, command, ledger, stderr), ledger, captured(stderr)).outcome
        end
      end

      def captured(path) = File.read(path, encoding: Encoding::UTF_8).scrub

      def launch(mirror, command, ledger, stderr)
        env, invocation = command
        pulse = "#{ledger}#{Kimera::Execution::IsolatedPlan::ChildCommand::PULSE}"
        waitfor(Process.spawn(env, *invocation, chdir: mirror, pgroup: true, out: File::NULL, err: stderr), pulse)
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
        when :git then Kimera::Execution::MirrorGit.new(plan.root).copy(target)
        end
      end

      def result(trial, **outcome) = MutantResult.new(mutant_id: trial.id, file: trial.file, **outcome)

      def error(trial, detail) = result(trial, status: :error, detail: detail)

      def now(reading = Process.clock_gettime(Process::CLOCK_MONOTONIC)) = reading
    end
  end
end
