# frozen_string_literal: true

require "digest"
require "json"

module KimeraEval
  # Ground truth for one mutant: its source baked into a copy of the project,
  # the whole suite run by the plain test command in a fresh process. Killed
  # when the command fails (or hangs); survived when it passes. Verdicts are
  # cached by project contents, command, file and baked source.
  class Oracle
    CACHE = File.join(ROOT, "eval", "tmp", "oracle-cache.json")
    LIMIT = 120
    JOBS = 4
    SKIPPED = %w[tmp/ log/ .git/ storage/].freeze

    Runner = Data.define(:command, :env)

    LOCK = Mutex.new

    def initialize(project, runner:, sandbox:)
      @project = project
      @runner = runner
      @sandbox = sandbox
    end

    def baseline!
      result = shell(copies.first).run(*@runner.command)
      return if result.ok?
      raise(SetupError, "oracle baseline is red in #{@project}:\n#{result.output.lines.last(40).join}")
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
      verdict(shell(copy).run(*@runner.command))
    end

    def verdict(result) = result.late? || !result.ok? ? "killed" : "survived"

    def shell(dir) = Shell.new(env: @runner.env, chdir: dir, timeout: LIMIT)

    def copies = @_copies ||= Array.new(JOBS) { @sandbox.copy(@project, "oracle") }

    def key(bake)
      Digest::SHA256.hexdigest([signature, @runner.command.join(" "), bake["file"], bake["source"]].join("\0"))
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
