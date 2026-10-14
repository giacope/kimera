# frozen_string_literal: true

require "fileutils"
require "tmpdir"

module KimeraEval
  # Disposable copies of fixtures, all under one workspace removed at exit.
  class Sandbox
    IDENTITY = %w[AUTHOR COMMITTER]
      .flat_map { |role| [["GIT_#{role}_NAME", "eval"], ["GIT_#{role}_EMAIL", "eval@example.com"]] }.to_h.freeze

    def initialize
      @count = 0
    end

    def root = @_root ||= Dir.mktmpdir("kimera-eval")

    def copy(source, name = File.basename(source))
      target = File.join(root, "#{name}-#{@count += 1}")
      FileUtils.mkdir_p(target)
      FileUtils.cp_r(File.join(source, "."), target)
      target
    end

    def git(dir)
      shell = Shell.new(chdir: dir, env: IDENTITY)
      shell.run("git", "init", "-q", "-b", "main")
      commit(shell, "fixture")
      dir
    end

    def commit(shell, message)
      shell.run("git", "add", "-A")
      shell.run("git", "commit", "-q", "-m", message)
    end

    def remove! = FileUtils.rm_rf(root)
  end
end
