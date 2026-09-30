# frozen_string_literal: true

require_relative "isolated_pulse"

module Kimera
  module Execution
    module IsolatedExecutionWatchdog
      private

      def waitfor(pid, pulse = File::NULL)
        watch = Kimera::Execution::IsolatedPulse.new(pulse, limit)
        loop do
          step = attempt(pid, watch)
          return step unless step == :continue
        end
      end

      def attempt(pid, watch)
        done, status = Process.waitpid2(pid, Process::WNOHANG)
        return status if done
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
      rescue Errno::ESRCH
        nil
      end

      def reap(pid)
        Process.waitpid(pid)
      rescue Errno::ECHILD
        nil
      end
    end
  end
end
