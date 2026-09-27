# frozen_string_literal: true

require "json"
require "kimera/execution/harness"
require "kimera/frameworks/adapter"
require "kimera/registry/builder"
require "timeout"

# The warm pool end to end: a hard-timeout verdict carries the killed
# worker's stacks, and a doubted kill is judged again on a fresh worker.
RSpec.describe(Kimera::Execution::Harness) do
  let(:registry) do
    Kimera::RegistryScan.new.source(<<~RUBY, file: "calc.rb")
      def a(x, y)
        x > y
      end
    RUBY
  end

  let(:ids) { registry.each.map { |m, _p| m.id } }

  after { Kimera::Runtime.reset! }

  def harness(adapter, **)
    described_class.new(registry: registry, adapter: adapter, **)
  end

  # Every covering test of an active mutant blocks in a method the dump can name.
  def hanging
    Class.new(Kimera::Frameworks::Adapter) do
      def source(_files) = self
      def test_ids = ["t1"]

      def run(_ids)
        wedge if Kimera::Runtime.active
        Kimera::Frameworks::RunOutcome.new(passed: true, failed_ids: [])
      end

      def wedge = sleep(30)
    end.new
  end

  it "puts a real worker's thread backtraces in a hard-timeout verdict", :aggregate_failures do
    report = Timeout.timeout(20) { harness(hanging, soft_timeout: nil, hard_timeout: 0.5).run(ids: [ids.first]) }
    detail = report.results.first.detail

    expect(report.results.first.status).to(eq(:timeout))
    expect(detail).to(start_with("hard watchdog timeout\nthreads in the worker when it was killed:\nmain thread ("))
    expect(detail).to(match(/harness_recheck_spec\.rb:\d+:in '[^']*wedge'/))
  end

  # The first worker doubts its first kill; every later worker kills, and
  # says so when the kill was a recheck.
  def doubting
    calls = 0
    lambda do |_slot|
      calls += 1
      doubter = calls == 1
      forked { |request, response| serve(request, response, doubter) }
    end
  end

  def serve(request, response, doubter)
    while (line = request.gets)
      ask = JSON.parse(line)
      break response.puts(JSON.generate(t: "requeue", id: ask["id"], detail: "t9 also failed")) if doubter
      answer(response, ask)
    end
    response.puts(JSON.generate(t: "done"))
    exit!(0)
  end

  def answer(response, ask)
    detail = ask["recheck"] ? "rechecked" : nil
    response.puts(JSON.generate(t: "result", id: ask["id"], status: "killed", fails: ["t1"], detail: detail))
    response.puts(JSON.generate(t: "ready"))
    response.flush
  end

  it "judges a requeued mutant on a fresh worker and reports the doubt as a leak", :aggregate_failures do
    report = Timeout.timeout(20) { harness(nil, spawner: doubting, hard_timeout: 5.0).run(ids: ids) }

    expect(report.results.map(&:status)).to(all(eq(:killed)))
    expect(report.results.count { |result| result.detail == "rechecked" }).to(eq(1))
    expect(report.leaks.map(&:detail)).to(eq(["t9 also failed"]))
    expect(report.leaks.map(&:mutant_id)).to(eq([ids.first]))
  end

  describe(Kimera::Execution::Verdicts) do
    let(:verdicts) { described_class.new(registry) }

    it "adds the worker's stacks to a hard-timeout verdict", :aggregate_failures do
      expect(verdicts.timeout(ids.first, 2.0, "threads: main").detail).to(eq("hard watchdog timeout\nthreads: main"))
      expect(verdicts.timeout(ids.first, 2.0).detail).to(eq("hard watchdog timeout"))
    end

    it "keeps a worker's detail on its verdict" do
      result = verdicts.parse("t" => "result", "id" => ids.first, "status" => "killed", "detail" => "Assertion: no")
      expect(result.detail).to(eq("Assertion: no"))
    end
  end
end
