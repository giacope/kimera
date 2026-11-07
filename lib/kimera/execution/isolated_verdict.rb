# frozen_string_literal: true

require_relative "bay"
require_relative "isolated_outcome"
require_relative "isolated_plan"
require_relative "pace"
require_relative "patience"

module Kimera
  module Execution
    module IsolatedVerdict
      ChildCommand = Kimera::Execution::IsolatedPlan::ChildCommand
      LEDGER = "ledger.json"
      STDERR_LOG = "stderr.log"

      private

      def evaluate(id, bay)
        _mutant, point, file = registry[id] { return error(id, nil, "unknown mutant") }
        bake(id, bay, point, file)
      rescue StandardError => error
        self.error(id, file, "#{error.class}: #{error.message}")
      end

      def single(id, slot = nil)
        synth = Overlay.new(registry)
        result = with_mirror { |mirror| evaluate(id, Kimera::Execution::Bay.new(mirror, slot, synth)) }
        return unstaged(result) if result.status?(:error)
        result.killed? ? confirmed(result, slot) : result
      end

      def unstaged(result)
        result.unstaged("the isolated tier could not stage it: ")
      end

      def confirmed(result, slot = nil)
        control = result.covering { |tests| control(tests, slot) }
        control.confirmed(result) { |contradiction| result.unjudged(contradiction) }
      end

      def control(tests, slot) = with_mirror { |mirror| verdict(Kimera::Execution::Bay.new(mirror, slot), tests) }

      def bake(id, bay, point, file)
        settled = plan.settled(id, point)
        return settled.fetch(0) unless settled.empty?
        tests = plan.tests(id, point)
        return result(id, file, status: :no_coverage, detail: point.reasons(Kimera::Reason.unsafety).first) unless tests
        outcome, duration = measure(id, bay, tests, file)
        result(id, file, duration: duration, covering_tests: tests, **outcome.to_h, **outcome.killing(quality?))
      end

      def measure(id, bay, tests, file)
        started = now
        ordered = Kimera::Execution::Pace.new(timings).fastest(tests)
        [cleared(bay, ordered, with_mutant(id, bay, file) { settle(bay, ordered) }), now - started]
      rescue Kimera::Overlay::Unbakeable => error
        [IsolatedOutcome.new(:unmutatable, nil, Kimera::Reason.unmutatable(error.message).to_s), nil]
      end

      def settle(bay, tests)
        verdict(bay, tests, first: !quality?).retried { verdict(bay, tests, first: !quality?) }
      end

      def cleared(bay, tests, outcome)
        outcome.cleared { with_mirror { |mirror| verdict(bay.moved(mirror), tests) } }
      end

      def with_mutant(id, bay, file)
        original, target = bay.stage(layout.root, file, id)
        yield
      ensure
        File.write(target, original) if original
      end

      def verdict(bay, locations, first: false)
        dirs.mktmpdir("kimera-ledger") do |dir|
          ledger = File.join(dir, LEDGER)
          seconds = patience(locations)
          exit = launch(bay, bay.command(plan, locations, ledger, first: first), dir, seconds)
          rulings.new(exit, ledger, captured(File.join(dir, STDERR_LOG)), seconds).outcome
        end
      end

      def captured(path) = File.read(path, encoding: Encoding::UTF_8).scrub

      def launch(bay, command, dir, seconds)
        started = bay.start(command, File.join(dir, STDERR_LOG))
        watchdog.waitfor(started, File.join(dir, "#{LEDGER}#{ChildCommand::PULSE}"), seconds)
      end

      def patience(locations) = Kimera::Execution::Patience.new(limit, timings: timings).longest(locations)

      def with_mirror
        dirs.mktmpdir("kimera-isolated") do |mirror|
          layout.populate(mirror)
          yield(mirror)
        end
      end

      def result(id, file, **outcome) = MutantResult.new(mutant_id: id, file: file, **outcome)

      def error(id, file, detail) = result(id, file, status: :error, detail: detail)

      def now(reading = Process.clock_gettime(Process::CLOCK_MONOTONIC)) = reading
    end
  end
end
