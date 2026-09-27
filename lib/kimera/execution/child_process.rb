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

      def kill(pid)
        Process.kill("KILL", pid)
      rescue Errno::ESRCH
        nil
      end

      def reap(pid)
        Process.wait(pid)
        $CHILD_STATUS
      rescue Errno::ECHILD
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
