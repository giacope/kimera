# frozen_string_literal: true

module KimeraEval
  class Repository
    IDENTITY = %w[AUTHOR COMMITTER]
      .flat_map { |role| [["GIT_#{role}_NAME", "eval"], ["GIT_#{role}_EMAIL", "eval@example.com"]] }.to_h.freeze

    def initialize(dir, shell = Shell.new(chdir: dir, env: IDENTITY))
      @shell = shell
    end

    def started
      git("init", "-q", "-b", "main")
      commit("fixture")
    end

    def git(*argv) = @shell.run("git", *argv)

    def commit(message)
      git("add", "-A")
      git("commit", "-q", "-m", message)
      self
    end
  end
end
