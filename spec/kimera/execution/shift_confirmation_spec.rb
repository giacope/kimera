# frozen_string_literal: true

require "json"
require "kimera/execution/shift"
require "kimera/frameworks/adapter"
require "kimera/registry/builder"
require "stringio"

# A warm kill counts only if the killing test passes with the mutant switched
# off and fails again with it on. Anything else is state the worker kept.
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

  after { Kimera::Runtime.reset! }

  # +script+ maps a test to the outcomes of its successive runs, as
  # [active?, passed?] pairs are consumed in order; unscripted runs pass.
  def scripted(script, failures: {})
    Class.new do
      attr_reader :log

      define_method(:initialize) do
        @script = script.transform_values(&:dup)
        @log = []
      end

      define_method(:test_ids) { script.keys }

      define_method(:run) do |ids|
        id = ids.first
        @log << [id, Kimera::Runtime.active]
        passed = @script.fetch(id, []).shift != :fail
        failed = passed ? [] : [id]
        Kimera::Frameworks::RunOutcome.new(
          passed: passed, failed_ids: failed, failures: failed.to_h { |t| [t, failures.fetch(t, "boom in #{t}")] }
        )
      end
    end.new
  end

  def worker(adapter, coverage, soft: nil)
    described_class.new(adapter: adapter, registry: registry, coverage: coverage, soft_timeout: soft, leak_every: 0)
  end

  def messages(io) = io.string.each_line.map { |line| JSON.parse(line) }

  describe "a confirmed kill" do
    it "runs the killer three times: mutant on, mutant off, mutant on", :aggregate_failures do
      target = ids.first
      adapter = scripted({ "t1" => %i[fail pass fail] })
      result = worker(adapter, { target => ["t1"] }).evaluate(target)

      expect(result.status).to(eq(:killed))
      expect(result.failing_tests).to(eq(["t1"]))
      expect(adapter.log).to(eq([["t1", target], ["t1", nil], ["t1", target]]))
    end

    it "records the killing test's failure as the detail" do
      target = ids.first
      adapter = scripted({ "t1" => %i[fail pass fail] }, failures: { "t1" => "Assertion: expected 1\n    t.rb:3" })
      expect(worker(adapter, { target => ["t1"] }).evaluate(target).detail).to(eq("Assertion: expected 1\n    t.rb:3"))
    end

    it "leaves a survivor's detail empty" do
      target = ids.first
      expect(worker(scripted({ "t1" => [] }), { target => ["t1"] }).evaluate(target).detail).to(be_nil)
    end

    it "remembers only a confirmed killer for the next mutant", :aggregate_failures do
      a, b = ids.first(2)
      adapter = scripted({ "slow" => [], "t1" => %i[fail pass pass], "t2" => %i[fail pass fail] })
      shift = worker(adapter, { a => %w[t1], b => %w[slow t2] })
      shift.evaluate(a)
      adapter.log.clear

      shift.evaluate(b)
      expect(adapter.log.first).to(eq(["slow", b]))
    end
  end

  describe "a kill that doesn't reproduce, in a warm worker" do
    def serve(adapter, coverage, requests)
      request = StringIO.new(requests.map { |id| "#{JSON.generate(id: id)}\n" }.join)
      response = StringIO.new
      worker(adapter, coverage).serve(request, response)
      messages(response)
    end

    it "asks for a recheck when the test also fails with the mutant switched off", :aggregate_failures do
      a, b = ids.first(2)
      adapter = scripted({ "t1" => %i[fail fail] }, failures: { "t1" => "Assertion: stale config\n    t.rb:9" })
      sent = serve(adapter, { a => ["t1"], b => ["t1"] }, [a, b])

      expect(sent.map { |message| message["t"] }).to(eq(%w[requeue done]))
      expect(sent.first["id"]).to(eq(a))
      expect(sent.first["detail"]).to(
        eq(
          "t1 also failed with the mutant switched off (Assertion: stale config), so state left by earlier " \
            "tests in its warm worker failed it, not the mutant; the mutant was judged again on a fresh worker"
        )
      )
      expect(adapter.log).to(eq([["t1", a], ["t1", nil]])) # and b never ran here
    end

    it "asks for a recheck when the test passes on its rerun with the mutant on", :aggregate_failures do
      target = ids.first
      sent = serve(scripted({ "t1" => %i[fail pass pass] }), { target => ["t1"] }, [target])

      expect(sent.first["t"]).to(eq("requeue"))
      expect(sent.first["detail"]).to(start_with("t1 passed when rerun with the mutant still on, so state left"))
    end

    it "names a control failure with no message" do
      target = ids.first
      sent = serve(scripted({ "t1" => %i[fail fail] }, failures: { "t1" => nil }), { target => ["t1"] }, [target])
      expect(sent.first["detail"]).to(start_with("t1 also failed with the mutant switched off (no message), so"))
    end

    it "keeps serving after a confirmed kill" do
      a, b = ids.first(2)
      sent = serve(scripted({ "t1" => %i[fail pass fail fail pass fail] }), { a => ["t1"], b => ["t1"] }, [a, b])
      expect(sent.map { |message| message["t"] }).to(eq(%w[result ready result ready done]))
    end
  end

  describe "the leak guard" do
    def guarded(adapter, coverage, cadence)
      described_class.new(
        adapter: adapter, registry: registry, coverage: coverage, soft_timeout: nil, leak_every: cadence
      )
    end

    it "skips its check after a suspect, since the worker is about to be recycled", :aggregate_failures do
      a, b = ids.first(2)
      adapter = scripted({ "t1" => %i[fail pass fail], "t2" => %i[fail fail] })
      request = StringIO.new("#{JSON.generate(id: a)}\n#{JSON.generate(id: b)}\n")
      response = StringIO.new
      guarded(adapter, { a => ["t1"], b => ["t2"] }, 2).serve(request, response)

      expect(messages(response).map { |message| message["t"] }).to(eq(%w[result ready requeue done]))
      expect(adapter.log.size).to(eq(5))
    end

    it "reports a leak when its re-run of a kill doesn't reproduce" do
      target = ids.first
      io = StringIO.new
      guarded(scripted({ "t1" => %i[fail pass fail fail fail] }), { target => ["t1"] }, 1).run([target], io)
      expect(messages(io).map { |message| message["t"] }).to(eq(%w[result leak done]))
    end
  end

  describe "a recheck on a fresh worker" do
    def recheck(adapter, coverage, id)
      request = StringIO.new("#{JSON.generate(id: id, recheck: true)}\n")
      response = StringIO.new
      worker(adapter, coverage).serve(request, response)
      messages(response)
    end

    it "leaves out a test that fails without the mutant and lets another confirm the kill", :aggregate_failures do
      target = ids.first
      adapter = scripted({ "t1" => %i[fail fail], "t2" => %i[fail pass fail] })
      sent = recheck(adapter, { target => %w[t1 t2] }, target)

      expect(sent.map { |message| message["t"] }).to(eq(%w[result ready done]))
      expect(sent.first).to(include("status" => "killed", "fails" => ["t2"]))
    end

    it "can't judge a mutant whose only failing test fails without it", :aggregate_failures do
      target = ids.first
      adapter = scripted({ "t1" => %i[fail fail], "t2" => [] }, failures: { "t1" => "Assertion: stale" })
      sent = recheck(adapter, { target => %w[t1 t2] }, target)

      expect(sent.first["status"]).to(eq("harness_error"))
      expect(sent.first["detail"]).to(
        eq(
          "t1 also failed with the mutant switched off (Assertion: stale) even on a fresh worker, and no other " \
            "covering test killed the mutant, so it can't be judged warm: fix the state that test depends on, " \
            "or judge the mutant with --isolated"
        )
      )
      expect(sent.map { |message| message["t"] }).to(eq(%w[result ready done]))
    end

    it "reports a clean survivor as survived" do
      target = ids.first
      sent = recheck(scripted({ "t1" => [] }), { target => %w[t1] }, target)
      expect(sent.first["status"]).to(eq("survived"))
    end

    it "treats only a true recheck flag as a recheck" do
      target = ids.first
      request = StringIO.new("#{JSON.generate(id: target, recheck: "yes")}\n")
      response = StringIO.new
      worker(scripted({ "t1" => %i[fail fail] }), { target => ["t1"] }).serve(request, response)
      expect(messages(response).first["t"]).to(eq("requeue"))
    end

    it "starts each mutant with no doubts left from the last one", :aggregate_failures do
      a, b = ids.first(2)
      adapter = scripted({ "t1" => %i[fail fail], "t2" => [] })
      shift = worker(adapter, { a => %w[t1], b => %w[t2] })

      expect(shift.evaluate(a, :recheck).status).to(eq(:harness_error))
      expect(shift.evaluate(b, :recheck).status).to(eq(:survived))
    end
  end

  describe "the soft timeout" do
    # Frameworks rescue Timeout's interrupt as a test error; pretend one did.
    def swallowing(delay)
      Class.new do
        define_method(:test_ids) { %w[t1 t2] }
        define_method(:run) do |ids|
          sleep(delay) if ids == ["t1"] && Kimera::Runtime.active
          Kimera::Frameworks::RunOutcome.new(passed: false, failed_ids: ids, failures: { ids.first => "interrupted" })
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
      expect(result.detail).to(eq("soft timeout (0.1s) expired while t1 ran"))
    end

    # Threads the interrupted test started may still hold locks; later mutants
    # on this worker would block on them and be scored killed.
    it "stops taking work after a timeout, so the pool replaces the worker", :aggregate_failures do
      first, second = ids.first(2)
      request = StringIO.new([first, second].map { |id| "#{JSON.generate(id: id)}\n" }.join)
      response = StringIO.new
      worker(swallowing(1.0), { first => %w[t1], second => %w[t2] }, soft: 0.1).serve(request, response)

      sent = messages(response)
      expect(sent.map { |m| m["t"] }).to(eq(%w[result done]))
      expect(sent.first).to(include("id" => first, "status" => "timeout"))
    end

    it "keeps taking work after a kill" do
      first, second = ids.first(2)
      request = StringIO.new([first, second].map { |id| "#{JSON.generate(id: id)}\n" }.join)
      response = StringIO.new
      worker(scripted({ "t1" => %i[fail pass fail] }), { first => %w[t1], second => %w[t1] }, soft: 5.0)
        .serve(request, response)

      expect(messages(response).map { |m| m["t"] }).to(eq(%w[result ready result ready done]))
    end

    it "still scores a failure inside the deadline as a kill" do
      target = ids.first
      adapter = scripted({ "t1" => %i[fail pass fail] })
      expect(worker(adapter, { target => ["t1"] }, soft: 5.0).evaluate(target).status).to(eq(:killed))
    end

    # The control run swallows the interrupt and passes; the rerun then fails.
    it "catches a deadline that passes during the confirmation runs" do
      target = ids.first
      adapter = scripted({ "t1" => [] })
      adapter.define_singleton_method(:run) do |ids|
        on = Kimera::Runtime.active
        begin
          sleep(1.0) unless on
        rescue Timeout::ExitException
          nil
        end
        Kimera::Frameworks::RunOutcome.new(passed: !on, failed_ids: on ? ids : [])
      end
      expect(worker(adapter, { target => ["t1"] }, soft: 0.1).evaluate(target).status).to(eq(:timeout))
    end
  end
end
