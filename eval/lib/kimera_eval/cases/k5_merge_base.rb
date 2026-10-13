# frozen_string_literal: true

module KimeraEval
  # K5: `--since main` on a feature branch. The branch changed alpha
  # (committed) and gamma (uncommitted); main moved on and changed beta after
  # the branch point. Only alpha's and gamma's mutants belong to the change.
  class MergeBaseCase < Case
    ID = "K5"
    TITLE = "--since diffs against the merge-base, keeping uncommitted work"
    EXPECTED = %w[alpha gamma].freeze

    def call
      dir = history(sandbox.git(sandbox.copy(fixture("diff"))))
      path = File.join(dir, "tmp", "since.json")
      result = checkout.kimera("run", "--since", "main", "--report", path, "--no-progress", chdir: dir)
      selected = File.exist?(path) ? methods(path) : []
      { "pass" => selected == EXPECTED, "summary" => { "selected" => selected.join("+"), "expected" => EXPECTED.join("+") } }
        .merge("exit" => result.code)
    end

    private

    def history(dir)
      git = Shell.new(chdir: dir, env: sandbox.identity)
      git.run("git", "checkout", "-q", "-b", "feature")
      change(dir, "x > 1", "x >= 2")
      sandbox.commit(git, "feature: alpha")
      git.run("git", "checkout", "-q", "main")
      change(dir, "x < 2", "x <= 1")
      sandbox.commit(git, "main: beta")
      git.run("git", "checkout", "-q", "feature")
      change(dir, "x == 3", "3 == x")
      dir
    end

    def change(dir, from, to)
      path = File.join(dir, "lib", "calc.rb")
      File.write(path, File.read(path).sub(from, to))
    end

    def methods(path) = JSON.parse(File.read(path))["results"].map { |row| row["method"] }.uniq.sort
  end
end
