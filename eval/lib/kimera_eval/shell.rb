# frozen_string_literal: true

require "open3"

module KimeraEval
  # Runs one command, capturing its output, wall time and the peak resident
  # memory of every process it starts (sampled from /proc).
  class Shell
    Result =
      Data.define(:status, :stdout, :stderr, :wall, :rss, :late) do
        def ok? = !late && status.success?

        def code = late ? nil : status.exitstatus

        def output = stdout + stderr

        def late? = late
      end

    INTERVAL = 0.05
    PAGE = 4096
    CLEARED = %w[BUNDLE_GEMFILE RUBYOPT BUNDLER_SETUP BUNDLE_BIN_PATH].to_h { |name| [name, nil] }.freeze

    def initialize(chdir:, env: {}, timeout: 600, input: nil)
      @env = env
      @chdir = chdir
      @timeout = timeout
      @input = input
    end

    def run(*argv)
      started = clock
      Open3.popen3(CLEARED.merge(@env), *argv, chdir: @chdir, pgroup: true) do |stdin, out, errors, waiter|
        feed(stdin)
        finish(waiter, [out, errors].map { |io| Thread.new { io.read } }, started)
      end
    end

    private

    def feed(stdin)
      stdin.write(@input) if @input
    rescue Errno::EPIPE
      nil
    ensure
      stdin.close
    end

    def finish(waiter, readers, started)
      peak = Peak.new(waiter.pid)
      sampler = Thread.new { peak.sample until waiter.join(INTERVAL) }
      status, late = wait(waiter)
      sampler.join
      Result.new(status, *readers.map { |reader| text(reader.value) }, clock - started, peak.to_h, late)
    end

    def text(bytes) = bytes.to_s.force_encoding(Encoding::UTF_8).scrub

    def wait(waiter)
      done = waiter.join(@timeout)
      stop(waiter) unless done
      [waiter.value, !done]
    end

    def stop(waiter)
      Process.kill("KILL", -waiter.pid)
    rescue Errno::ESRCH
      false
    end

    def clock(now = Process.clock_gettime(Process::CLOCK_MONOTONIC)) = now

    # Peak RSS across a process tree: the largest single process, and the
    # largest sum at any one sample.
    class Peak
      def initialize(root)
        @root = root
      end

      def sample
        sizes = tree.to_h { |pid| [pid, rss(pid)] }
        sizes.each { |pid, bytes| seen[pid] = [seen[pid], bytes].max }
        totals << sizes.values.sum
      end

      def to_h
        { "max_process_mb" => megabytes([0, *seen.values].max), "max_tree_mb" => megabytes([0, *totals].max) }
          .merge("processes" => seen.size)
      end

      private

      def seen = @_seen ||= Hash.new(0)

      def totals = @_totals ||= []

      def megabytes(bytes) = (bytes / 1024.0 / 1024).round(1)

      def tree
        parents = table
        found = [@root]
        found.each { |pid| found.concat(parents.fetch(pid, [])) }
        found
      end

      def table
        Dir.glob("/proc/[0-9]*/stat").each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |path, children|
          fields = stat(path)
          children[Integer(fields[1])] << Integer(fields[0]) if fields
        end
      end

      def stat(path)
        text = File.read(path)
        [text[/\A\d+/], text[(text.rindex(")") + 2)..].split[1]]
      rescue SystemCallError, NoMethodError
        nil
      end

      def rss(pid)
        Integer(File.read("/proc/#{pid}/statm").split[1]) * PAGE
      rescue SystemCallError, ArgumentError
        0
      end
    end
  end
end
