# frozen_string_literal: true

module KimeraEval
  class AncestryCase < Case
    ID = "K5"
    TITLE = "--since diffs against the merge-base, keeping uncommitted work"
    EXPECTED = %w[alpha gamma].freeze
    STEPS = [
      [%w[checkout -q -b feature], "x > 1", "x >= 2", "feature: alpha"],
      [%w[checkout -q main], "x < 2", "x <= 1", "main: beta"],
      [%w[checkout -q feature], "x == 3", "3 == x"]
    ].freeze

    def call
      dir = history(sandbox.copy(fixture("diff")))
      path = File.join(dir, "tmp", "since.json")
      arguments = ["run", "--since", "main", "--since-scope", "lines", "--report", path, "--no-progress"]
      exit, = checkout.cli(*arguments, chdir: dir)
      judge(File.exist?(path) ? methods(path) : []).merge(exit.exited)
    end

    private

    def judge(selected)
      { "pass" => selected == EXPECTED }
        .merge("summary" => { "selected" => selected.join("+"), "expected" => EXPECTED.join("+") })
    end

    def history(dir)
      repository = sandbox.repository(dir)
      path = File.join(dir, "lib", "calc.rb")
      STEPS.each do |switch, from, to, *message|
        apply(repository, path, switch, [from, to])
        message.each { |text| repository.commit(text) }
      end
      dir
    end

    def apply(repository, path, switch, edit)
      repository.git(*switch)
      File.write(path, File.read(path).sub(*edit))
    end

    def methods(path) = JSON.parse(File.read(path))["results"].map { |row| row["method"] }.uniq.sort
  end
end
