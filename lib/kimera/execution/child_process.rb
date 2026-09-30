# frozen_string_literal: true

require "English"
require "json"

module Kimera
  module Execution
    module ChildProcess
      private

      def silence!
        STDOUT.reopen(File::NULL, "w")
        STDERR.reopen(File::NULL, "w")
        $stdout = STDOUT
        $stderr = STDERR
      end

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

      def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
