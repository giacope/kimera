# frozen_string_literal: true

require "fileutils"
require "tmpdir"

module KimeraEval
  class Sandbox
    IDENTITY = %w[AUTHOR COMMITTER]
      .flat_map { |role| [["GIT_#{role}_NAME", "eval"], ["GIT_#{role}_EMAIL", "eval@example.com"]] }.to_h.freeze

    def initialize(dirs = Dir)
      @dirs = dirs
    end

    def root = @_root ||= @dirs.mktmpdir("kimera-eval")

    def copy(source, name = File.basename(source))
      target = File.join(root, "#{name}-#{copies.next}")
      FileUtils.mkdir_p(target)
      FileUtils.cp_r(File.join(source, "."), target)
      target
    end

    def shell(dir) = Shell.new(chdir: dir, env: IDENTITY)

    def git(dir)
      shell = shell(dir)
      shell.run("git", "init", "-q", "-b", "main")
      commit(shell, "fixture")
      dir
    end

    def commit(shell, message)
      shell.run("git", "add", "-A")
      shell.run("git", "commit", "-q", "-m", message)
    end

    def remove! = FileUtils.rm_rf(root)

    private

    def copies = @_copies ||= (1..).each
  end
end
