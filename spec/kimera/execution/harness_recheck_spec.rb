# frozen_string_literal: true

require "json"
require "kimera/execution/harness"
require "kimera/frameworks/suite"
require "kimera/registry/builder"
require "timeout"

using ResultFields

RSpec.describe(Kimera::Execution::Harness) do
  let(:registry) do
    Kimera::RegistryScan.new.source(<<~RUBY, file: "calc.rb")
      def a(x, y)
        x > y
      end
    RUBY
  end

  let(:ids) { registry.each.map { |m, _p| m.to_i } }

  def harness(adapter, **)
    described_class.build(registry: registry, adapter: adapter, **)
  end

  def hanging
    Class.new(Kimera::Frameworks::Suite) do
      def source(_files) = self
      def test_ids = ["t1"]

      def run(_ids)
        wedge if Kimera::RUNTIME.active
        Kimera::Frameworks::RunOutcome.new(passed: true, failed_ids: [])
      end

      def wedge = sleep(30)
    end.new
  end

  it "puts a real worker's thread backtraces in a hard-timeout verdict", :aggregate_failures do
    report = Timeout.timeout(20) { harness(hanging, soft_timeout: nil, hard_timeout: 0.5).run(ids: [ids.first]) }
    detail = report.to_a.first.detail

    expect([report.to_a.first.status, report.to_a.first.duration]).to(eq([:timeout, 0.5]))
    expect(detail).to(start_with("hard watchdog timeout\nthreads in the worker when it was killed:\nmain thread ("))
    expect(detail).to(match(/harness_recheck_spec\.rb:\d+:in '[^']*wedge'/))
  end

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

    expect(report.to_a.map(&:status)).to(all(eq(:killed)))
    expect(report.to_a.count { |result| result.detail == "rechecked" }).to(eq(1))
    expect(report.notes.to_h["leaks"].map(&:detail)).to(eq(["t9 also failed"]))
    expect(report.notes.to_h["leaks"].map(&:mutant_id)).to(eq([ids.first]))
  end

  describe(Kimera::Execution::Verdicts) do
    let(:verdicts) { described_class.new(registry) }

    it "adds the worker's stacks to a hard-timeout verdict", :aggregate_failures do
      expect(verdicts.timeout(ids.first, 2.0, ["threads: main"]).detail).to(eq("hard watchdog timeout\nthreads: main"))
      expect(verdicts.timeout(ids.first, 2.0).detail).to(eq("hard watchdog timeout"))
    end

    it "keeps a worker's detail on its verdict" do
      result = verdicts.parse("t" => "result", "id" => ids.first, "status" => "killed", "detail" => "Assertion: no")
      expect(result.detail).to(eq("Assertion: no"))
    end
  end
end
