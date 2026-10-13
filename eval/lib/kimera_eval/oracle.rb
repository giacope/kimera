# frozen_string_literal: true

require "digest"
require "json"

module KimeraEval
  # Ground truth for one mutant: its source baked into a copy of the project,
  # the whole suite run by the plain test command in a fresh process. Killed
  # when the command fails (or hangs); survived when it passes. Verdicts are
  # cached by project contents, file and baked source.
  class Oracle
    CACHE = File.join(ROOT, "eval", "tmp", "oracle-cache.json")
    LIMIT = 120

    def initialize(project, command:, sandbox:, env: {}, jobs: 4)
      @project = project
      @command = command
      @sandbox = sandbox
      @env = env
      @jobs = jobs
    end

    def baseline!
      result = shell(copies.first).run(*@command)
      raise("oracle baseline is red in #{@project}:\n#{result.output[-3000..] || result.output}") unless result.ok?
    end

    def verdicts(baked)
      pending = baked.reject { |_id, bake| bake["error"] || cache.key?(key(bake)) }
      judge(pending.to_a)
      save
      baked.to_h { |id, bake| [id, bake["error"] ? "unbakeable" : cache.fetch(key(bake))] }
    end

    private

    def judge(work)
      queue = Queue.new
      work.each { |item| queue << item }
      threads = copies.map { |copy| Thread.new { drain(queue, copy) } }
      threads.each(&:join)
    end

    def drain(queue, copy)
      loop do
        _id, bake = queue.pop(true)
        verdict = trial(copy, bake)
        lock.synchronize { cache[key(bake)] = verdict }
      end
    rescue ThreadError
      nil
    end

    def trial(copy, bake)
      path = File.join(copy, bake["file"])
      original = File.binread(path)
      File.write(path, bake["source"])
      result = Shell.new(env: @env, chdir: copy, timeout: LIMIT).run(*@command)
      verdict(result)
    ensure
      File.binwrite(path, original) if original
    end

    def verdict(result)
      return "killed" if result.timed_out?
      result.ok? ? "survived" : "killed"
    end

    def shell(dir) = Shell.new(env: @env, chdir: dir, timeout: LIMIT)

    def copies = @copies ||= Array.new(@jobs) { @sandbox.copy(@project, "oracle") }

    def lock = @lock ||= Mutex.new

    def key(bake) = Digest::SHA256.hexdigest([signature, @command.join(" "), bake["file"], bake["source"]].join("\0"))

    def signature
      @signature ||= Digest::SHA256.hexdigest(
        Dir.glob("**/*", File::FNM_DOTMATCH, base: @project).sort
          .reject { |file| file.start_with?("tmp/", "log/", ".git/") || File.directory?(File.join(@project, file)) }
          .map { |file| "#{file}\0#{Digest::SHA256.file(File.join(@project, file)).hexdigest}" }.join("\n")
      )
    end

    def cache = @cache ||= File.exist?(CACHE) ? JSON.parse(File.read(CACHE)) : {}

    def save
      FileUtils.mkdir_p(File.dirname(CACHE))
      File.write(CACHE, JSON.generate(cache))
    end
  end
end
