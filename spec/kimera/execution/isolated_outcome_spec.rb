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

  def test_judge_unreported(exit, ledger, stderr = "")
    Dir.mktmpdir do |dir|
      path = File.join(dir, "ledger.json")
      File.write(path, ledger) if ledger
      described_class.judge(exit, path, stderr)
    end
  end

  it "does not score a child that wrote no ledger as killed or survived", :aggregate_failures do
    expect(test_judge(failed, nil).status).to(eq(:harness_error))
    expect(test_judge(clean, nil).status).to(eq(:harness_error))
  end

  it "treats a ledger that is not an object as unreported", :aggregate_failures do
    expect(test_judge(failed, "[]").status).to(eq(:harness_error))
    expect(test_judge(clean, "[]").status).to(eq(:harness_error))
  end

  it "treats a failure count that is not an integer as unreported", :aggregate_failures do
    expect(test_judge(failed, { failures: "0" }.to_json).status).to(eq(:harness_error))
    expect(test_judge(clean, { failing: [] }.to_json).status).to(eq(:harness_error))
  end

  it "treats a ledger that is not JSON as unreported" do
    expect(test_judge(failed, "{not json").status).to(eq(:harness_error))
  end

  it "explains an unreported child with its exit status and both ends of a long stderr", :aggregate_failures do
    stderr = (1..30).map { |n| "line #{n}\n" }.join
    outcome = test_judge_unreported(failed, nil, stderr)
    kept = [*(1..5).map { |n| "line #{n}" }, "…", *(16..30).map { |n| "line #{n}" }]
    expect(outcome.failing).to(be_nil)
    expect(outcome.detail).to(eq("test child exited 1 without reporting results:\n#{kept.join("\n")}"))
  end

  it "keeps a stderr of exactly twenty lines whole" do
    stderr = (1..20).map { |n| "line #{n}\n" }.join
    expect(test_judge_unreported(failed, nil, stderr).detail)
      .to(end_with(":\n#{(1..20).map { |n| "line #{n}" }.join("\n")}"))
  end

  it "names the signal and omits an empty stderr for an unreported child" do
    outcome = test_judge_unreported(test_exit("Process.kill(:KILL, Process.pid)"), nil, "  \n")
    expect(outcome.detail).to(eq("test child died on signal 9 without reporting results"))
  end

  it "names the signal when a child with no failures dies on one", :aggregate_failures do
    outcome = test_judge(test_exit("Process.kill(:KILL, Process.pid)"), { failures: 0, failing: [] }.to_json)
    expect(outcome.status).to(eq(:harness_error))
    expect(outcome.detail).to(start_with("suite died on signal 9 with 0 failures"))
  end

  it "keeps a load error the child recorded as the kill's detail", :aggregate_failures do
    outcome = test_judge(failed, { failures: 1, failing: [], load_error: "ArgumentError: boom" }.to_json)
    expect(outcome.status).to(eq(:killed))
    expect(outcome.detail).to(eq("ArgumentError: boom"))
  end

  describe "#explain" do
    it "says why a red isolated baseline is red", :aggregate_failures do
      expect(described_class.new(:timeout).explain(30)).to(eq("timed out after 30s"))
      expect(described_class.new(:killed, %w[a b], "ignored").explain(1)).to(eq("failing: a, b"))
      expect(described_class.new(:killed, [], "LoadError: x").explain(1)).to(eq("LoadError: x"))
      expect(described_class.new(:harness_error).explain(1)).to(eq("the test child failed without naming a test"))
    end
  end

  it "treats a missing failing list on a kill as no named tests" do
    expect(test_judge(failed, { failures: 2 }.to_json).failing).to(eq([]))
  end
end
