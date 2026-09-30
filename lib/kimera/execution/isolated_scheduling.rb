# frozen_string_literal: true

require_relative "sweep"
require_relative "trial"

module Kimera
  module Execution
    module IsolatedExecutionScheduling
      private

      def ids
        plan.registry.each.map { |m, _p| m.id }
      end

      def serially(ids)
        sweep = Kimera::Execution::Sweep.new(ids, Mutex.new)
        with_mirror { |mirror| scan(sweep, mirror) }
        sweep.results
      end

      def scan(sweep, mirror)
        synth = Overlay.new(plan.registry)
        sweep.each { |id| charge(sweep, evaluate(Kimera::Execution::Trial.new(id, mirror, synth))) }
      end

      def concurrently(ids)
        sweep = Kimera::Execution::Sweep.new(ids, Mutex.new)
        workers(sweep).each(&:join)
        sweep.results
      end

      def workers(sweep)
        Array.new(jobs) { Thread.new { work(sweep) } }
      end

      def work(sweep)
        synth = Overlay.new(plan.registry)
        with_mirror { |mirror| drain(sweep, mirror, synth) }
      end

      def drain(sweep, mirror, synth)
        while (id = sweep.pop)
          charge(sweep, evaluate(Kimera::Execution::Trial.new(id, mirror, synth)))
        end
      end

      def alone(ids)
        sweep = Kimera::Execution::Sweep.new(ids, Mutex.new)
        Array.new(jobs) { Thread.new { solo(sweep) } }.each(&:join)
        sweep.results.to_h { |result| [result.mutant_id, result] }
      end

      def solo(sweep)
        while (id = sweep.pop)
          charge(sweep, single(id))
        end
      end

      def charge(sweep, result)
        done = sweep.record(result)
        progress.tick(result.status)
        trace(result, done, sweep.total)
      end
    end
  end
end
