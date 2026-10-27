# frozen_string_literal: true

require "json"
require "kimera/execution/shift"
require "kimera/frameworks/suite"
require "kimera/registry/builder"
require "stringio"

# No fork needed: feed a fake adapter, read the newline-JSON from a StringIO.
RSpec.describe(Kimera::Execution::Shift) do
  # A test fails when the active mutant is in its catch set. Runs with no
  # mutant active (a kill's control run) go to +controls+, not +runs+.
  let(:test_adapter_class) do
    Class.new do
      attr_reader :runs, :controls

      def initialize(catches: {}, failure: nil, timeout: nil)
        @catches = catches   # test_id => [mutant_id, ...]
        @failure = failure   # mutant id that makes a run raise
        @timeout = timeout   # mutant id that makes a run sleep
        @runs = []
        @controls = []
      end

      def test_ids = @catches.keys

      def run(ids)
        active = Kimera::RUNTIME.active
        (active ? @runs : @controls) << ids
        raise(RuntimeError, "boom") if active && active == @failure
        sleep(5) if active && active == @timeout
        failed = ids.select { |id| Array(@catches[id]).include?(active) }
        Kimera::Frameworks::RunOutcome.new(passed: failed.empty?, failed_ids: failed)
      end
    end
  end

  let(:registry) do
    Kimera::RegistryScan.new.source(<<~RUBY, file: "calc.rb")
      def a(x, y)
        x > y
      end
    RUBY
  end

  let(:ids) { registry.each.map { |m, _p| m.id } }
  let(:io) { StringIO.new }
  let(:response) { StringIO.new }

  def messages(io)
    io.string.each_line.map { |l| JSON.parse(l) }
  end

  def worker(coverage: nil, catches: {}, adapter: nil, **settings)
    described_class.new(
      adapter: adapter || test_adapter_class.new(catches: catches),
      registry: registry, coverage: coverage,
      soft_timeout: nil, zygote: InlineZygote.new, **settings
    )
  end

  def request(*names) = StringIO.new(names.map { |name| "#{JSON.generate(id: name)}\n" }.join)

  describe "#run streaming protocol" do
    it "emits a result for each mutant and a final done", :aggregate_failures do
      worker(coverage: ids.to_h { |id| [id, ["t1"]] }).run(ids, io)
      notes = messages(io)
      expect(notes.count { |m| m["t"] == "result" }).to(eq(ids.size))
      expect(notes.last["t"]).to(eq("done"))
    end

    it "marks a mutant survived when no covering test fails" do
      worker(catches: { "t1" => [] }, coverage: ids.to_h { |id| [id, ["t1"]] }).run(ids, io)
      results = messages(io).select { |m| m["t"] == "result" }
      expect(results.map { |r| r["status"] }.uniq).to(eq(["survived"]))
    end

    it "marks a mutant killed when a covering test catches it", :aggregate_failures do
      target = ids.first
      worker(catches: { "t1" => [target] }, coverage: { target => ["t1"] }).run([target], io)
      result = messages(io).find { |m| m["t"] == "result" }
      expect(result["status"]).to(eq("killed"))
      expect(result["fails"]).to(eq(["t1"]))
    end
  end

  describe "#run result message shape" do
    def killed_result
      target = ids.first
      worker(catches: { "t1" => [target] }, coverage: { target => ["t1"] }).run([target], io)
      messages(io).find { |m| m["t"] == "result" }
    end

    it "emits every documented field on a result message" do
      expect(killed_result.keys).to(contain_exactly("t", "id", "status", "ms", "fails", "cover", "detail"))
    end

    it "names the mutant, its verdict, and its failing and covering tests" do
      expect(killed_result.slice("id", "status", "fails", "cover"))
        .to(eq("id" => ids.first, "status" => "killed", "fails" => ["t1"], "cover" => ["t1"]))
    end

    # The `-`=>`+` mutant would make this about twice a clock read.
    it "times the mutant in milliseconds" do
      expect(killed_result["ms"]).to(be_a(Numeric).and(be >= 0.0).and(be < 1.0))
    end

    it "reports the status as its string name (not a symbol or object)" do
      target = ids.first
      worker(catches: { "t1" => [] }, coverage: { target => ["t1"] }).run([target], io)
      result = messages(io).find { |m| m["t"] == "result" }
      expect(result["status"]).to(eq("survived"))
    end
  end

  describe "#serve pool protocol" do
    def served
      coverage = { ids.first => ["t1"], ids.last => ["t1"] }
      worker(catches: { "t1" => [ids.first] }, coverage: coverage).serve(request(ids.first, ids.last), response)
      messages(response)
    end

    it "answers each id with result/ready and closes with done" do
      expect(served.map { |m| m["t"] }).to(eq(%w[result ready result ready done]))
    end

    it "judges each id it is asked" do
      results = served.select { |m| m["t"] == "result" }
      expect(results.map { |m| [m["id"], m["status"]] }).to(eq([[ids.first, "killed"], [ids.last, "survived"]]))
    end

    it "resets the active mutant when the request pipe closes" do
      target = ids.first
      Kimera::RUNTIME.active = 999
      request = StringIO.new("#{JSON.generate(id: target)}\n")
      worker(catches: { "t1" => [] }, coverage: { target => ["t1"] }).serve(request, response)
      expect(Kimera::RUNTIME.active).to(be_nil)
    end
  end

  describe "#evaluate classification" do
    def evaluate(id, coverage:, **)
      described_class.new(
        adapter: test_adapter_class.new(**),
        registry: registry, coverage: coverage,
        soft_timeout: nil, zygote: InlineZygote.new
      ).evaluate(id)
    end

    it "returns :no_coverage when no test exercises the mutant", :aggregate_failures do
      result = evaluate(ids.first, coverage: { ids.first => [] })
      expect(result.status).to(eq(:no_coverage))
      expect(result.duration).to(eq(0.0))
    end

    # Coverage is per mutated expression, not per line: another mutant on the
    # same line may well be covered (R6B1-M2).
    it "says no test reached the code it mutates, not that none ran its line" do
      detail = evaluate(ids.first, coverage: { ids.first => [] }).detail
      expect(detail).to(start_with("no test reached the code it mutates (other code on its line may have run)"))
    end

    it "uses the whole suite when coverage is nil" do
      result = evaluate(ids.first, coverage: nil, catches: { "t1" => [ids.first] })
      expect(result.status).to(eq(:killed))
    end

    it "classifies a raised error as :error with a Class: message detail", :aggregate_failures do
      target = ids.first
      result = evaluate(target, coverage: { target => ["t1"] }, catches: { "t1" => [] }, failure: target)
      expect(result.status).to(eq(:error))
      expect(result.detail).to(eq("RuntimeError: boom"))
      expect(result.duration).to(eq(0.0))
    end

    # Outside the test process (a broken adapter, say) the error is the real
    # one, not the zygote's report of it.
    it "names the class of an error raised outside the test process" do
      subject = Kimera::Execution::Shift::Subject.new(ids.first, "calc.rb")
      expect(subject.crashed(ArgumentError.new("bad"), 1.0).detail).to(eq("ArgumentError: bad"))
    end

    it "rules a Timeout::Error a timeout that took the limit", :aggregate_failures do
      result = Kimera::Execution::Shift::Subject.new(ids.first, "calc.rb").crashed(Timeout::Error.new("slow"), 2.0)
      expect([result.status, result.duration, result.detail]).to(eq([:timeout, 2.0, "slow"]))
    end

    # The pool's worker dies the same way, so the parent sees the death.
    it "lets the death of the test process through, unjudged" do
      dead = Class.new { def call = raise(Kimera::Execution::Zygote::Died.new("gone", code: 3)) }.new
      worker = described_class.new(
        adapter: test_adapter_class.new(catches: { "t1" => [] }), registry: registry,
        coverage: { ids.first => ["t1"] }, zygote: dead
      )
      expect { worker.evaluate(ids.first) }.to(raise_error(Kimera::Execution::Zygote::Died, "gone"))
    end

    it "runs each test in a forked zygote unless told otherwise" do
      worker = described_class.new(adapter: test_adapter_class.new, registry: registry)
      expect(worker.__send__(:zygote)).to(be_an_instance_of(Kimera::Execution::Zygote))
    end

    it "classifies a soft-timeout hang as :timeout carrying the soft-timeout" do
      target = ids.first
      adapter = test_adapter_class.new(catches: { "t1" => [] }, timeout: target)
      result = worker(adapter: adapter, coverage: { target => ["t1"] }, soft_timeout: 0.2).evaluate(target)
      expect(result).to(have_attributes(status: :timeout, duration: be >= 0.2, file: "calc.rb"))
    end

    it "records the point's file on a normal verdict" do
      target = ids.first
      result = evaluate(target, coverage: { target => ["t1"] }, catches: { "t1" => [] })
      expect(result.file).to(eq("calc.rb"))
    end

    # Pins `index[id]&.file` against the `&.`=>`.` mutant.
    it "tolerates an id absent from the registry (nil file, no raise)", :aggregate_failures do
      absent = ids.max + 10_000
      result = evaluate(absent, coverage: nil, catches: { "t1" => [] })
      expect(result.status).to(eq(:survived))
      expect(result.file).to(be_nil)
    end

    # Its first test resets the selector, as Kimera's own specs do in
    # after-hooks; its second catches whichever mutant is active.
    def resetting
      Class.new do
        def test_ids = %w[t_reset t_catch]
        define_method(:run) do |test_ids|
          t = test_ids.first
          Kimera::RUNTIME.reset! if t == "t_reset"
          failed = t == "t_catch" && Kimera::RUNTIME.active ? [t] : []
          Kimera::Frameworks::RunOutcome.new(passed: failed.empty?, failed_ids: failed)
        end
      end.new
    end

    # Without re-selecting, later tests see no active mutant and it falsely survives.
    it "re-selects the mutant before each covering test despite a resetting example" do
      target = ids.first
      result = worker(adapter: resetting, coverage: { target => %w[t_reset t_catch] }).evaluate(target)
      expect([result.status, result.failing_tests]).to(eq([:killed, ["t_catch"]]))
    end

    it "stops running covering tests at the first failure", :aggregate_failures do
      target = ids.first
      adapter = test_adapter_class.new(catches: { "t1" => [target], "t2" => [target] })
      worker = worker(adapter: adapter, coverage: { target => %w[t1 t2] })
      expect(worker.evaluate(target).status).to(eq(:killed))
      expect(adapter.runs).to(eq([["t1"]])) # t2 never ran
    end

    # "slow" comes first in both mutants' covering sets, so only reordering skips it.
    def killer_pair
      a, b = ids.first(2)
      adapter = test_adapter_class.new(catches: { "slow" => [], "killer" => [a, b] })
      [adapter, worker(adapter: adapter, coverage: { a => %w[slow killer], b => %w[slow killer] })]
    end

    it "walks the covering set in order on the first mutant", :aggregate_failures do
      adapter, shift = killer_pair
      expect(shift.evaluate(ids.first).status).to(eq(:killed))
      expect(adapter.runs).to(eq([["slow"], ["killer"], ["killer"]]))
    end

    # The walk stops at the first failure, so order decides how many tests run.
    it "tries the most recent killer first on the next mutant", :aggregate_failures do
      adapter, shift = killer_pair
      shift.evaluate(ids.first)
      adapter.runs.clear
      expect(shift.evaluate(ids[1]).status).to(eq(:killed))
      expect(adapter.runs).to(eq([["killer"]])) # slow skipped this time
    end

    # A duplicate would take a RECENT_KILLERS slot and evict "x" one kill early.
    it "keeps a re-killed test from consuming ledger capacity" do
      memory = Kimera::Execution::Shift::KillerMemory.new
      %w[x a b].each { |t| memory.remember(t) }
      memory.remember("a") # re-kill: move, not append
      13.times { |i| memory.remember("c#{i}") }

      # x is the 16th most recent distinct killer, so still kept.
      expect(memory.order(%w[z x])).to(eq(%w[x z]))
    end

    it "retains exactly RECENT_KILLERS killers, evicting oldest-first", :aggregate_failures do
      memory = Kimera::Execution::Shift::KillerMemory.new
      (1..17).each { |i| memory.remember("k#{i}") }

      # k2 is the 16th most recent, so kept. k1 was evicted.
      expect(memory.order(%w[z k2])).to(eq(%w[k2 z]))
      expect(memory.order(%w[z k1])).to(eq(%w[z k1]))
    end

    # Ties and tests the baseline never timed keep their coverage order.
    it "tries the covering set fastest first by baseline time" do
      pace = Kimera::Execution::Pace.new({ "slow" => 2.0, "fast" => 0.1, "mid" => 0.5, "tie" => 0.5 })
      memory = Kimera::Execution::Shift::KillerMemory.new(pace)
      expect(memory.order(%w[slow untimed mid fast tie])).to(eq(%w[fast mid tie slow untimed]))
    end

    it "still tries a recent killer before a faster test" do
      memory = Kimera::Execution::Shift::KillerMemory.new(Kimera::Execution::Pace.new({ "slow" => 2.0, "fast" => 0.1 }))
      memory.remember("slow")
      expect(memory.order(%w[fast slow])).to(eq(%w[slow fast]))
    end

    it "runs the covering test the baseline timed fastest first" do
      a = ids.first
      adapter = test_adapter_class.new(catches: { "ka" => [a], "kb" => [a] })
      worker = described_class.new(
        adapter: adapter, registry: registry, coverage: { a => %w[ka kb] },
        soft_timeout: nil, zygote: InlineZygote.new, timings: { "ka" => 0.9, "kb" => 0.1 }
      )
      expect(worker.evaluate(a).failing_tests).to(eq(["kb"]))
    end

    # Two mutants, each caught by its own test; both tests cover both.
    def crossed
      a, b = ids.first(2)
      adapter = test_adapter_class.new(catches: { "ka" => [a], "kb" => [b] })
      [adapter, worker(adapter: adapter, coverage: { a => %w[ka kb], b => %w[ka kb] })]
    end

    it "kills the first mutant with its own test, which it then promotes" do
      _, shift = crossed
      expect(shift.evaluate(ids.first).failing_tests).to(eq(["ka"]))
    end

    it "still runs the rest of the covering set after the promoted tests" do
      adapter, shift = crossed
      shift.evaluate(ids.first)
      adapter.runs.clear
      expect([shift.evaluate(ids[1]).status, adapter.runs]).to(eq([:killed, [["ka"], ["kb"], ["kb"]]]))
    end

    it "looks up coverage by integer or string mutant id" do
      target = ids.first
      result = evaluate(target, coverage: { target.to_s => ["t1"] }, catches: { "t1" => [target] })
      expect(result.status).to(eq(:killed))
    end

    it "runs only the mapped covering tests when coverage is present", :aggregate_failures do
      target = ids.first
      adapter = test_adapter_class.new(catches: { "t1" => [], "t2" => [target], "t3" => [] })
      worker = worker(adapter: adapter, coverage: { target => ["t1"] })
      # t2 would kill if the whole suite ran.
      expect(worker.evaluate(target).status).to(eq(:survived))
      expect(adapter.runs).to(eq([["t1"]]))
    end

    # The `||`=>`&&` mutant would read a passing outcome as killed.
    it "classifies a passing (non-nil) outcome as survived" do
      target = ids.first
      result = evaluate(target, coverage: { target => ["t1"] }, catches: { "t1" => [] })
      expect(result.status).to(eq(:survived))
    end

    # The real harness passes a default-proc Hash. A [] lookup would insert on a
    # miss and break the string-key fallback.
    def defaulting = Hash.new { |h, k| h[k] = [] }.tap { |coverage| coverage[ids.first] = ["t1"] }

    it "finds a mutant in a default-proc coverage map" do
      expect(evaluate(ids.first, coverage: defaulting, catches: { "t1" => [ids.first] }).status).to(eq(:killed))
    end

    it "does not auto-insert into a default-proc coverage map on a miss", :aggregate_failures do
      coverage = defaulting
      expect(evaluate(ids.last, coverage: coverage, catches: {}).status).to(eq(:no_coverage))
      expect(coverage.key?(ids.last)).to(be(false))
    end
  end

  describe "isolation lifecycle" do
    def counting(resets)
      Class.new do
        define_method(:around) { |&block| block.call }
        define_method(:reset!) { resets << true }
      end.new
    end

    it "resets isolation after every mutant, even a passing one" do
      resets = []
      shift = worker(catches: { "t1" => [] }, coverage: { ids.first => ["t1"] }, isolation: counting(resets))
      shift.run([ids.first], io)
      expect(resets.size).to(eq(1))
    end
  end

  describe "#coverage protocol" do
    def covered
      worker(catches: { "t1" => [], "t2" => [] }).coverage(request("t1", "t2"), response)
      messages(response)
    end

    it "answers each test id with result + ready and closes with done", :aggregate_failures do
      notes = covered
      expect(notes.map { |m| m["t"] }).to(eq(%w[result ready result ready done]))
      expect(notes.select { |m| m["t"] == "result" }.map { |m| m["id"] }).to(eq(%w[t1 t2]))
      expect(notes[1]).to(eq("t" => "ready"))
    end

    # When self-hosted, the loop's own guards land in the ledger too.
    it "reports each test's result with what it touched", :aggregate_failures do
      result = covered.first
      expect(result.keys).to(contain_exactly("t", "id", "touched", "passed", "failure", "took"))
      expect(result).to(include("passed" => true, "touched" => an_instance_of(Array)))
    end

    it "leaves no ledger behind when the request pipe closes" do
      worker = worker(catches: { "t1" => [] })
      request = StringIO.new("#{JSON.generate(id: "t1")}\n")
      expect { worker.coverage(request, StringIO.new) }
        .not_to(change { Array(Kimera::RUNTIME.instance_variable_get(:@ledgers)).size })
    end

    it "resets active and stops coverage when the request pipe closes", :aggregate_failures do
      request = StringIO.new("#{JSON.generate(id: "t1")}\n")
      # No mutant has this id (they count from 1): when self-hosted, a real id would
      # switch that mutant on for the rest of the example.
      Kimera::RUNTIME.active = -1
      worker(catches: { "t1" => [] }).coverage(request, response)
      expect(Kimera::RUNTIME.active).to(be_nil)
      expect(messages(response).last).to(eq("t" => "done"))
    end

    def touching
      Class.new do
        def test_ids = %w[t1 t2]
        define_method(:run) do |test_ids|
          Kimera::RUNTIME.active?(7) if test_ids == ["t1"]
          Kimera::RUNTIME.active?(8) if test_ids == ["t2"]
          Kimera::Frameworks::RunOutcome.new(passed: true, failed_ids: [])
        end
      end.new
    end

    # Of 7 and 8, what each test touched; when self-hosted, the loop's own guards add ids.
    def touched
      worker(adapter: touching).coverage(request("t1", "t2"), response)
      messages(response).select { |m| m["t"] == "result" }.map { |m| m["touched"] & [7, 8] }
    end

    it "reports the mutation points each example touches, drained per example" do
      expect(touched).to(eq([[7], [8]]))
    end
  end
end
