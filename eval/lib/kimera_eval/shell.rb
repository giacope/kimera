# frozen_string_literal: true

require "open3"
require "timeout"

module KimeraEval
  # Runs one command, capturing its output, wall time and the peak resident
  # memory of every process it starts (sampled from /proc).
  class Shell
    Result =
      Data.define(:status, :out, :err, :wall, :rss) do
        def ok? = status&.success?

        def code = status&.exitstatus

        def output = out + err

        def timed_out? = status.nil?
      end

    INTERVAL = 0.05
    PAGE = 4096

    def initialize(env: {}, chdir: Dir.pwd, timeout: 600, input: nil)
      @env = env
      @chdir = chdir
      @timeout = timeout
      @input = input
    end

    def run(*argv)
      started = clock
      Open3.popen3(clean.merge(@env), *argv, chdir: @chdir, pgroup: true) do |stdin, out, err, waiter|
        feed(stdin)
        finish(waiter, [out, err].map { |io| Thread.new { io.read } }, started)
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

    def clean = { "BUNDLE_GEMFILE" => nil, "RUBYOPT" => nil, "BUNDLER_SETUP" => nil, "BUNDLE_BIN_PATH" => nil }

    def finish(waiter, readers, started)
      peak = Peak.new(waiter.pid)
      sampler = Thread.new { peak.sample until waiter.join(INTERVAL) }
      status = wait(waiter)
      sampler.join
      Result.new(status, *readers.map { |reader| reader.value.to_s.force_encoding(Encoding::UTF_8).scrub }, clock - started,
                 peak.to_h)
    end

    def wait(waiter)
      return waiter.value if waiter.join(@timeout)
      Process.kill("KILL", -waiter.pid)
      waiter.value
      nil
    rescue Errno::ESRCH
      waiter.value
    end

    def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    # Peak RSS across a process tree: the largest single process, and the
    # largest sum at any one sample.
    class Peak
      def initialize(root)
        @root = root
        @single = 0
        @total = 0
        @each = Hash.new(0)
      end

      def sample
        sizes = tree.to_h { |pid| [pid, rss(pid)] }
        sizes.each { |pid, bytes| @each[pid] = [@each[pid], bytes].max }
        @single = [@single, *sizes.values].max
        @total = [@total, sizes.values.sum].max
      end

      def to_h = { "max_process_mb" => mb(@single), "max_tree_mb" => mb(@total), "processes" => @each.size }

      private

      def mb(bytes) = (bytes / 1024.0 / 1024).round(1)

      def tree
        parents = table
        found = [@root]
        found.each { |pid| found.concat(parents.fetch(pid, [])) }
        found
      end

      def table
        Dir.glob("/proc/[0-9]*/stat").each_with_object(Hash.new { |h, k| h[k] = [] }) do |path, children|
          fields = stat(path)
          children[Integer(fields[1])] << Integer(fields[0]) if fields
        end
      end

      def stat(path)
        text = File.read(path)
        pid = text[/\A\d+/]
        rest = text[(text.rindex(")") + 2)..].split
        [pid, rest[1]]
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
