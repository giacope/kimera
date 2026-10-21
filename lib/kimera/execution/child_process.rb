# frozen_string_literal: true

require "English"
require "json"

module Kimera
  module Execution
    module ChildProcess
      private

      def silence!
        $stdout = discard(1)
        $stderr = discard(2)
      end

      def discard(descriptor) = IO.for_fd(descriptor, autoclose: false).reopen(File::NULL, "w")

      def lead
        Process.setpgid(0, 0)
      rescue SystemCallError
        nil
      end

      def kill(pid)
        [-pid, pid].each { |target| signal(target) }
      end

      def reap(pid)
        Process.wait(pid)
        $CHILD_STATUS
      rescue Errno::ECHILD
        nil
      end

      def stop(pid)
        kill(pid)
        reap(pid)
      end

      def bury(pid)
        reap(pid).tap { signal(-pid) }
      end

      def signal(target)
        Process.kill("KILL", target)
      rescue Errno::ESRCH, Errno::EPERM
        nil
      end

      def shut(io)
        io.close
      rescue IOError
        nil
      end

      def parse(line)
        JSON.parse(line.dup.force_encoding(Encoding::UTF_8).scrub)
      rescue JSON::ParserError
        nil
      end

      def now(reading = Process.clock_gettime(Process::CLOCK_MONOTONIC)) = reading
    end
  end
end
