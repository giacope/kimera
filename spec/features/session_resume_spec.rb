# frozen_string_literal: true

RSpec.describe("kimera run --session after the tests change (end-to-end)", :aggregate_failures) do
  def gate = "module Gate\n  def self.open?(load)\n    load > 5 && load <= 50\n  end\nend\n"

  def checks
    { "opens under load" => [20, true], "stays shut at 5" => [5, false], "opens at 50" => [50, true] }
      .merge("shuts above 50" => [51, false])
  end

  def examples(names)
    body = names.map { |name| format("  it(%p) { expect(Gate.open?(%d)).to be(%s) }", name, *checks[name]) }
    "require_relative \"../app/gate\"\n\nRSpec.describe Gate do\n#{body.join("\n")}\nend\n"
  end

  def resumed
    test_tree({ "app/gate.rb" => gate, "spec/gate_spec.rb" => examples(checks.keys) }, "kimera-session") do |root|
      session = ["--session", File.join(root, "session.json")]
      first = test_outcome(cwd: root, arguments: session).verdicts
      File.write(File.join(root, "spec", "gate_spec.rb"), examples(["opens under load", "opens at 50"]))
      [first, test_outcome(cwd: root, arguments: session).verdicts, test_outcome(cwd: root).verdicts]
    end
  end

  it "judges again every mutant once a test it was judged by is deleted" do
    first, again, fresh = resumed
    expect(again).to(eq(fresh))
    expect(first).not_to(eq(fresh))
  end
end
