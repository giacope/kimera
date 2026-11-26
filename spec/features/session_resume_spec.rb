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

  def configuration(value) = "module Settings; MIN = #{value}; end\n"

  def configured
    source = "require_relative \"../config/settings\"\n#{gate.sub("> 5", "> Settings::MIN")}"
    { "app/gate.rb" => source, "spec/gate_spec.rb" => examples(checks.keys), "config/settings.rb" => configuration(5) }
  end

  def reconfigured
    test_tree(configured, "kimera-session-config") do |root|
      flags = ["--operators", "comparison", "--no-reuse-coverage"]
      session = [*flags, "--session", File.join(root, "session.json")]
      first = test_outcome(cwd: root, arguments: session)
      File.write(File.join(root, "config", "settings.rb"), configuration(6))
      [first, test_outcome(cwd: root, arguments: session), test_outcome(cwd: root, arguments: flags)]
    end
  end

  it "fails the resumed gate when changed configuration leaves a boundary untested" do
    first, again, fresh = reconfigured
    expect([first.status, again.status, fresh.status]).to(eq([0, 2, 2]))
    expect([first.counts["survived"], again.counts["survived"]]).to(eq([0, 1]))
    expect(again.verdicts).to(eq(fresh.verdicts))
  end
end
