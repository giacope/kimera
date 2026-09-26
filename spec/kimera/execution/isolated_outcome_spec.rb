# frozen_string_literal: true

require "json"
require "tmpdir"
require "kimera/execution/isolated_outcome"

RSpec.describe(Kimera::Execution::IsolatedOutcome) do
  def test_exit(script)
    Process.wait2(Process.spawn(Gem.ruby, "-e", script)).last
  end

  def test_judge(exit, ledger)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "ledger.json")
      File.write(path, ledger) if ledger
      described_class.judge(exit, path)
    end
  end

  let(:failed) { test_exit("exit 1") }
  let(:clean) { test_exit("exit 0") }

  it "falls back to the exit status when the ledger is not an object", :aggregate_failures do
    expect(test_judge(failed, "[]").status).to(eq(:killed))
    expect(test_judge(clean, "[]").status).to(eq(:survived))
  end

  it "falls back to the exit status when the failure count is not an integer", :aggregate_failures do
    expect(test_judge(failed, { failures: "0" }.to_json).status).to(eq(:killed))
    expect(test_judge(clean, { failing: [] }.to_json).status).to(eq(:survived))
  end

  it "falls back to the exit status when the ledger is not JSON" do
    expect(test_judge(failed, "{not json").status).to(eq(:killed))
  end

  it "names the signal when a child with no failures dies on one", :aggregate_failures do
    outcome = test_judge(test_exit("Process.kill(:KILL, Process.pid)"), { failures: 0, failing: [] }.to_json)
    expect(outcome.status).to(eq(:harness_error))
    expect(outcome.detail).to(start_with("suite exited on signal 9 with 0 failures"))
  end

  it "treats a missing failing list on a kill as no named tests" do
    expect(test_judge(failed, { failures: 2 }.to_json).failing).to(eq([]))
  end
end
