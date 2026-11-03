# frozen_string_literal: true

require "digest"
require "json"

module KimeraEval
  class Oracle
    CACHE = File.join(ROOT, "eval", "tmp", "oracle-cache.json")
    LIMIT = 120
    JOBS = 4
    SKIPPED = %w[tmp/ log/ .git/ storage/].freeze

    class Suite
      def initialize(command, env)
        @command = command
        @env = env
      end

      def run(dir, timeout) = Shell.new(env: @env, chdir: dir, timeout: timeout).run(*@command)

      def to_s = @command.join(" ")
    end

    LOCK = Mutex.new

    def initialize(project, suite:, sandbox:)
      @project = project
      @suite = suite
      @sandbox = sandbox
    end

    def baseline!
      exit, printed = @suite.run(copies.first, LIMIT)
      return if exit.ok?
      raise(SetupError, "oracle baseline is red in #{@project}:\n#{printed.output.lines.last(40).join}")
    end

    def verdicts(baked)
      judge(baked.reject { |_id, bake| bake["error"] || cache.key?(key(bake)) }.values)
      save
      baked.transform_values { |bake| bake["error"] ? "unbakeable" : cache.fetch(key(bake)) }
    end

    private

    def judge(work)
      queue = Queue.new(work).tap(&:close)
      workers =
        copies.map do |copy|
          Thread.new do
            while (bake = queue.pop)
              settle(copy, bake)
            end
          end
        end
      workers.each(&:join)
    end

    def settle(copy, bake)
      verdict = trial(copy, bake)
      LOCK.synchronize { cache[key(bake)] = verdict }
    end

    def trial(copy, bake)
      path = File.join(copy, bake["file"])
      original = File.binread(path)
      ran(copy, path, bake["source"])
    ensure
      File.binwrite(path, original) if original
    end

    def ran(copy, path, source)
      File.write(path, source)
      exit, = @suite.run(copy, LIMIT)
      exit.ok? ? "survived" : "killed"
    end

    def copies = @_copies ||= Array.new(JOBS) { @sandbox.copy(@project, "oracle") }

    def key(bake)
      Digest::SHA256.hexdigest([signature, @suite.to_s, bake["file"], bake["source"]].join("\0"))
    end

    def signature = @_signature ||= Digest::SHA256.hexdigest(files.map { |file| "#{file}\0#{digest(file)}" }.join("\n"))

    def files
      Dir.glob("**/*", File::FNM_DOTMATCH, base: @project)
        .reject { |file| file.start_with?(*SKIPPED) || File.directory?(File.join(@project, file)) }
    end

    def digest(file) = Digest::SHA256.file(File.join(@project, file)).hexdigest

    def cache = @_cache ||= File.exist?(CACHE) ? JSON.parse(File.read(CACHE)) : {}

    def save
      FileUtils.mkdir_p(File.dirname(CACHE))
      File.write(CACHE, JSON.generate(cache))
    end
  end
end
