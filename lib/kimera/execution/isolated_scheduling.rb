# frozen_string_literal: true

require_relative "bay"
require_relative "sweep"

module Kimera
  module Execution
    module IsolatedScheduling
      private

      def ids
        registry.each.map { |m, _p| m.id }
      end

      def serially(ids, tick)
        sweep = Kimera::Execution::Sweep.new(ids, Mutex.new, tick)
        with_mirror { |mirror| scan(sweep, mirror) }
        sweep.results
      end

      def scan(sweep, mirror)
        bay = Kimera::Execution::Bay.new(mirror, nil, Overlay.new(registry))
        sweep.each { |id| charge(sweep, evaluate(id, bay)) }
      end

      def concurrently(ids, tick)
        sweep = Kimera::Execution::Sweep.new(ids, Mutex.new, tick)
        workers(sweep).each(&:join)
        sweep.results
      end

      def workers(sweep)
        Array.new(jobs) { |slot| Thread.new { work(sweep, slot) } }
      end

      def work(sweep, slot)
        synth = Overlay.new(registry)
        with_mirror { |mirror| drain(sweep, Kimera::Execution::Bay.new(mirror, slot, synth)) }
      end

      def drain(sweep, bay)
        sweep.drain { |id| charge(sweep, evaluate(id, bay)) }
      end

      def alone(ids, tick)
        sweep = Kimera::Execution::Sweep.new(ids, Mutex.new, tick)
        Array.new(jobs) { |slot| Thread.new { solo(sweep, jobs > 1 ? slot : nil) } }.each(&:join)
        sweep.results.to_h { |result| [result.mutant_id, result] }
      end

      def solo(sweep, slot)
        sweep.drain { |id| charge(sweep, single(id, slot)) }
      end

      def charge(sweep, result) = sweep.record(result)
    end
  end
end
