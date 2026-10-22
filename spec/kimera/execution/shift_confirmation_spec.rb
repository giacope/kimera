# frozen_string_literal: true

require "json"
require "kimera/execution/shift"
require "kimera/frameworks/suite"
require "kimera/registry/builder"
require "stringio"

# Each mutant runs in a process of its own; a kill counts only if the killing
# test fails again with the mutant on in another fresh process, alone, or
# after the same covering tests, which then pass it with the mutant off.
RSpec.describe(Kimera::Execution::Shift) do
  let(:registry) do
    Kimera::RegistryScan.new.source(<<~RUBY, file: "calc.rb")
      def a(x, y)
        x > y
      end

      def b(x, y)
        x < y
      end
    RUBY
  end

  let(:ids) { registry.each.map { |m, _p| m.id } }

  # +script+ maps a test to the outcomes of its successive runs, consumed in
  # order; unscripted runs pass.
  let(:scripted_class) do
    Class.new do
      attr_reader :log

      def initialize(script, failures)
        @script = script.transform_values(&:dup)
        @test_ids = script.keys
        @failures = failures
        @log = []
      end

      attr_reader :test_ids

      def run(ids)
        id = ids.first
        @log << [id, Kimera::RUNTIME.active]
        failed = @script.fetch(id, []).shift == :fail ? [id] : []
        messages = failed.to_h { |t| [t, @failures.fetch(t, "boom in #{t}")] }
        Kimera::Frameworks::RunOutcome.new(passed: failed.empty?, failed_ids: failed, failures: messages)
      end
    end
  end

  def scripted(script, failures: {}) = scripted_class.new(script, failures)

  def worker(adapter, coverage, soft: nil)
    described_class.new(
      adapter: adapter, registry: registry, coverage: coverage, soft_timeout: soft, zygote: InlineZygote.new
    )
  end

  def messages(io) = io.string.each_line.map { |line| JSON.parse(line) }

  def serve(adapter, coverage, requests, soft: nil)
    request = StringIO.new(requests.map { |id| "#{JSON.generate(id: id)}\n" }.join)
    response = StringIO.new
    worker(adapter, coverage, soft: soft).serve(request, response)
    messages(response)
  end

  describe "a confirmed kill" do
    # The coverage pass ran it without the mutant, first in a fresh process too.
    it "takes a failing first test as the kill, running it once", :aggregate_failures do
      target = ids.first
      adapter = scripted({ "t1" => %i[fail] })
      result = worker(adapter, { target => ["t1"] }).evaluate(target)
      expect([result.status, result.failing_tests]).to(eq([:killed, ["t1"]]))
      expect(adapter.log).to(eq([["t1", target]]))
    end

    it "confirms a later test's failure by running it alone", :aggregate_failures do
      target = ids.first
      adapter = scripted({ "t0" => [], "t1" => %i[fail fail] })
      result = worker(adapter, { target => %w[t0 t1] }).evaluate(target)

      expect(result.failing_tests).to(eq(["t1"]))
      expect(adapter.log).to(eq([["t0", target], ["t1", target], ["t1", target]]))
    end

    it "records the failure as the detail" do
      target = ids.first
      adapter = scripted({ "t1" => %i[fail fail] }, failures: { "t1" => "Assertion: expected 1\n    t.rb:3" })
      expect(worker(adapter, { target => ["t1"] }).evaluate(target).detail).to(eq("Assertion: expected 1\n    t.rb:3"))
    end

    it "leaves a survivor's detail empty" do
      target = ids.first
      expect(worker(scripted({ "t1" => [] }), { target => ["t1"] }).evaluate(target).detail).to(be_nil)
    end

    it "remembers only a confirmed killer for the next mutant", :aggregate_failures do
      a, b = ids.first(2)
      adapter = scripted({ "slow" => [], "t1" => %i[fail pass pass], "t2" => %i[fail fail] })
      worker(adapter, { a => %w[t1], b => %w[slow t2] }).tap { |shift| shift.evaluate(a) }.evaluate(b)
      expect(adapter.log.find { |_test, active| active == b }).to(eq(["slow", b]))
    end
  end

  describe "a kill that needs the covering tests before it" do
    it "confirms it by rerunning them, with the mutant off and then on", :aggregate_failures do
      target = ids.first
      adapter = scripted({ "t0" => [], "t1" => %i[fail pass pass fail] })
      result = worker(adapter, { target => %w[t0 t1] }).evaluate(target)
      expect([result.status, result.failing_tests]).to(eq([:killed, ["t1"]]))
      expect(adapter.log).to(
        eq([["t0", target], ["t1", target], ["t1", target], ["t0", nil], ["t1", nil], ["t0", target], ["t1", target]])
      )
    end

    it "can't judge a mutant whose only failing test also fails without it", :aggregate_failures do
      target = ids.first
      adapter = scripted({ "t0" => [], "t1" => %i[fail pass fail] }, failures: { "t1" => "Assertion: stale" })
      result = worker(adapter, { target => %w[t0 t1] }).evaluate(target)

      expect(result.status).to(eq(:harness_error))
      expect(result.detail).to(
        eq(
          "t1 also failed with the mutant switched off (Assertion: stale), each run in a fresh process after the " \
            "covering tests before it, and no other covering test killed the mutant, so it can't be judged warm: " \
            "fix the state that test depends on, or judge the mutant with --isolated"
        )
      )
    end

    it "names a control failure with no message" do
      target = ids.first
      adapter = scripted({ "t0" => [], "t1" => %i[fail pass fail] }, failures: { "t1" => nil })
      expect(worker(adapter, { target => %w[t0 t1] }).evaluate(target).detail).to(
        start_with("t1 also failed with the mutant switched off (no message), each run")
      )
    end

    it "doesn't count a failure that doesn't come back with the mutant on", :aggregate_failures do
      target = ids.first
      adapter = scripted({ "t0" => [], "t1" => %i[fail pass pass pass] })
      result = worker(adapter, { target => %w[t0 t1] }).evaluate(target)
      expect(result.status).to(eq(:harness_error))
      expect(result.detail).to(start_with("t1 passed when rerun with the mutant still on, each run in a fresh"))
    end

    it "lets a later covering test confirm the kill a doubtful one could not", :aggregate_failures do
      target = ids.first
      adapter = scripted({ "t0" => [], "t1" => %i[fail pass fail], "t2" => %i[fail] })
      result = worker(adapter, { target => %w[t0 t1 t2] }).evaluate(target)

      expect(result.status).to(eq(:killed))
      expect(result.failing_tests).to(eq(["t2"]))
    end

    it "starts each mutant with no doubts left from the last one", :aggregate_failures do
      a, b = ids.first(2)
      adapter = scripted({ "t0" => [], "t1" => %i[fail pass fail], "t2" => [] })
      shift = worker(adapter, { a => %w[t0 t1], b => %w[t2] })

      expect(shift.evaluate(a).status).to(eq(:harness_error))
      expect(shift.evaluate(b).status).to(eq(:survived))
    end
  end

  describe "the pool protocol" do
    it "answers every mutant, doubtful or not, and asks for no recheck" do
      a, b = ids.first(2)
      sent = serve(scripted({ "t1" => %i[fail pass fail fail fail] }), { a => ["t1"], b => ["t1"] }, [a, b])
      expect(sent.map { |message| message["t"] }).to(eq(%w[result ready result ready done]))
    end

    it "ignores a recheck flag: every mutant is judged in fresh processes anyway" do
      target = ids.first
      request = StringIO.new("#{JSON.generate(id: target, recheck: true)}\n")
      response = StringIO.new
      worker(scripted({ "t1" => %i[fail fail] }), { target => ["t1"] }).serve(request, response)
      expect(messages(response).first).to(include("t" => "result", "status" => "killed"))
    end
  end

  describe "the soft timeout" do
    # Frameworks rescue Timeout's interrupt as a test error; pretend one did.
    # With the mutant off the tests pass at once.
    def swallowing(delay)
      Class.new do
        define_method(:test_ids) { %w[t1 t2] }
        define_method(:run) do |ids|
          on = Kimera::RUNTIME.active
          sleep(delay) if ids == ["t1"] && on
          Kimera::Frameworks::RunOutcome.new(passed: !on, failed_ids: ids, failures: { ids.first => "interrupted" })
        rescue Timeout::ExitException
          Kimera::Frameworks::RunOutcome.new(passed: false, failed_ids: ids, failures: { ids.first => "interrupted" })
        end
      end.new
    end

    it "scores a test failing past the deadline as a timeout, not a kill", :aggregate_failures do
      target = ids.first
      result = worker(swallowing(1.0), { target => %w[t1 t2] }, soft: 0.1).evaluate(target)

      expect(result.status).to(eq(:timeout))
      expect(result.failing_tests).to(be_nil)
      expect(result.detail).to(start_with("soft timeout (0.1s) expired while t1 ran with the mutant on; alone with"))
    end

    # The interrupted test's threads die with its process, so the worker
    # keeps serving.
    it "keeps taking work after a timeout", :aggregate_failures do
      first, second = ids.first(2)
      sent = serve(swallowing(1.0), { first => %w[t1], second => %w[t2] }, [first, second], soft: 0.1)
      expect(sent.map { |m| m["t"] }).to(eq(%w[result ready result ready done]))
      expect(sent.first).to(include("id" => first, "status" => "timeout"))
    end

    it "still scores a failure inside the deadline as a kill" do
      target = ids.first
      adapter = scripted({ "t1" => %i[fail fail] })
      expect(worker(adapter, { target => ["t1"] }, soft: 5.0).evaluate(target).status).to(eq(:killed))
    end

    # The control run, mutant off, is the one that runs past the deadline: the
    # test is slow on its own, so its timeout says nothing about the mutant.
    # Sleeps past the deadline, interrupted or not.
    def idle
      sleep(1.0)
    rescue Timeout::ExitException
      nil
    end

    # Slow with the mutant off; with it on, t1 fails only its first run.
    def slow_off
      runs = Hash.new(0)
      nap = method(:idle)
      scripted({ "t0" => [], "t1" => [] }).tap do |adapter|
        adapter.define_singleton_method(:run) do |ids|
          on = Kimera::RUNTIME.active
          nap.call unless on
          passed = !on || ids == ["t0"] || (runs[ids] += 1) > 1
          Kimera::Frameworks::RunOutcome.new(passed: passed, failed_ids: passed ? [] : ids)
        end
      end
    end

    it "lays no timeout on the mutant when the deadline passes during a run with it off", :aggregate_failures do
      result = worker(slow_off, { ids.first => %w[t0 t1] }, soft: 0.1).evaluate(ids.first)
      expect(result.status).to(eq(:harness_error))
      expect(result.detail).to(include("also failed with the mutant switched off (soft timeout (0.1s) expired"))
    end
  end
end
