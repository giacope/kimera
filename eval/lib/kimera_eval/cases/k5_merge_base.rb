# frozen_string_literal: true

module KimeraEval
  # K5: `--since main` on a feature branch. The branch changed alpha
  # (committed) and gamma (uncommitted); main moved on and changed beta after
  # the branch point. Only alpha's and gamma's mutants belong to the change.
  class AncestryCase < Case
    ID = "K5"
    TITLE = "--since diffs against the merge-base, keeping uncommitted work"
    EXPECTED = %w[alpha gamma].freeze
    Step = Data.define(:switch, :from, :to, :message)
    STEPS = [
      Step.new(%w[checkout -q -b feature], "x > 1", "x >= 2", "feature: alpha"),
      Step.new(%w[checkout -q main], "x < 2", "x <= 1", "main: beta"),
      Step.new(%w[checkout -q feature], "x == 3", "3 == x", nil)
    ].freeze

    def call
      dir = history(sandbox.git(sandbox.copy(fixture("diff"))))
      path = File.join(dir, "tmp", "since.json")
      result = checkout.cli("run", "--since", "main", "--report", path, "--no-progress", chdir: dir)
      judge(File.exist?(path) ? methods(path) : []).merge("exit" => result.code)
    end

    private

    def judge(selected)
      { "pass" => selected == EXPECTED }
        .merge("summary" => { "selected" => selected.join("+"), "expected" => EXPECTED.join("+") })
    end

    def history(dir)
      git = Shell.new(chdir: dir, env: Sandbox::IDENTITY)
      STEPS.each { |step| apply(git, File.join(dir, "lib", "calc.rb"), step) }
      dir
    end

    def apply(git, path, step)
      git.run("git", *step.switch)
      File.write(path, File.read(path).sub(step.from, step.to))
      sandbox.commit(git, step.message) if step.message
    end

    def methods(path) = JSON.parse(File.read(path))["results"].map { |row| row["method"] }.uniq.sort
  end
end
