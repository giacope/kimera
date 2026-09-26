# frozen_string_literal: true

module Kimera
  module Execution
    module IsolatedExecutionWatchdog
      private

      def waitfor(pid)
        deadline = now + limit
        loop do
          step = attempt(pid, deadline)
          return step unless step == :continue
        end
      end

      def attempt(pid, deadline)
        done, status = Process.waitpid2(pid, Process::WNOHANG)
        return status if done
        return fail!(pid) unless (deadline - now).positive?
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
      rescue Errno::ESRCH
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
