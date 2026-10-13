# frozen_string_literal: true

require "fileutils"
require "tmpdir"

module KimeraEval
  # Disposable copies of fixtures, all under one workspace removed at exit.
  class Sandbox
    def initialize(root = Dir.mktmpdir("kimera-eval"))
      @root = root
      @count = 0
    end

    attr_reader :root

    def copy(source, name = File.basename(source))
      target = File.join(@root, "#{name}-#{@count += 1}")
      FileUtils.mkdir_p(target)
      FileUtils.cp_r(File.join(source, "."), target)
      target
    end

    def git(dir)
      git = Shell.new(chdir: dir, env: identity)
      git.run("git", "init", "-q", "-b", "main")
      commit(git, "fixture")
      dir
    end

    def commit(shell, message)
      shell.run("git", "add", "-A")
      shell.run("git", "commit", "-q", "-m", message)
    end

    def identity
      { "GIT_AUTHOR_NAME" => "eval", "GIT_AUTHOR_EMAIL" => "eval@example.com" }
        .merge("GIT_COMMITTER_NAME" => "eval", "GIT_COMMITTER_EMAIL" => "eval@example.com")
    end

    def remove! = FileUtils.rm_rf(@root)
  end
end
