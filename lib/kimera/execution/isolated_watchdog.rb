# frozen_string_literal: true

require_relative "isolated_pulse"

module Kimera
  module Execution
    module IsolatedExecutionWatchdog
      private

      def waitfor(pid, pulse = File::NULL)
        outlast(pid, Kimera::Execution::IsolatedPulse.new(pulse, limit))
      rescue SignalException
        fail!(pid)
        raise
      end

      def outlast(pid, watch)
        loop do
          step = attempt(pid, watch)
          return step unless step == :continue
        end
      end

      def attempt(pid, watch)
        done, status = Process.waitpid2(pid, Process::WNOHANG)
        return status.tap { kill(pid) } if done
        return fail!(pid) if watch.expired?
        pause
        :continue
      end

      def pause
        sleep(@options.fetch(:poll_interval, 0.05))
      end

      def fail!(pid)
        kill(pid)
        reap(pid)
        :timeout
      end

      def kill(pid)
        Process.kill("KILL", -pid)
      rescue Errno::ESRCH, Errno::EPERM
        nil
      end

      def reap(pid)
        Process.waitpid(pid)
      rescue Errno::ECHILD
        nil
      end

      def trace(result, done, total)
        return if progress.enabled?
        errors.puts(line(result, done, total))
      end

      def line(result, done, total)
        format(
          "kimera: isolated %d/%d  #%s %s  %s  (%.1fs)", done, total,
          *result.to_h.values_at("mutant_id", "status", "file", "duration")
        )
      end
    end
  end
end
