# frozen_string_literal: true

require "kimera/cli"
require "kimera/cli/run"
require "kimera/cli/run/pass"
require "kimera/cli/survivors"
require "kimera/execution/baseline_failure"
require "kimera/execution/callback"
require "kimera/execution/shift"
require "kimera/execution/worker_pool"
require "kimera/incremental/session"
require "kimera/registry/mutation_point"
require "kimera/results/result"

RSpec.describe(Kimera::Execution::BaselineFailure, :aggregate_failures) do
  it "renders the complete baseline failure, including boundaries and omitted details" do
    limit = Kimera::Execution::BaselineFailure::MAX_MESSAGE
    failed = %w[a b c d]
    messages = { "a" => "one\ntwo", "b" => "x" * (limit + 1), "c" => nil }

    expect(described_class.summary(failed, messages, "rspec a b c --order defined")).to(
      eq(
        "baseline suite is not green: a, b, c, d\n  " \
          "a:\n    one\n    two\n  " \
          "b:\n    #{"x" * limit}…\n  " \
          "reproduce without kimera: rspec a b c --order defined"
      )
    )
    expect(described_class.summary(["a"], {}, "ruby -n a")).to(
      eq("baseline suite is not green: a\n  reproduce without kimera: ruby -n a")
    )
    expect(described_class.truncate("y" * limit)).to(eq("y" * limit))
  end

  it "breaks a red parallel baseline down per worker, in the order each ran its tests" do
    workers = { 1 => %w[p q r s t u v], 0 => %w[a b], 2 => %w[c] }
    failed = %w[s u c x1 x2 x3 x4 x5]
    workers[1].push(*%w[x1 x2 x3 x4 x5])

    expect(described_class.summary(failed, {}, "cmd", workers: workers)).to(
      eq(
        "baseline suite is not green: #{failed.join(", ")}\n  " \
          "per worker (tests in the order it ran them):\n    " \
          "worker 1: ran 12; failed #4 s, #6 u, #8 x1, #9 x2, #10 x3 (+2 more); just before: p, q, r\n    " \
          "worker 2: ran 1; failed #1 c (first test on this worker)\n  " \
          "reproduce without kimera: cmd"
      )
    )
  end

  it "renders a red isolated baseline with its reason indented and the mirror hint" do
    error = described_class.mirrored("E: x\n  at a.rb:1", "  hint")
    expect(error).to(be_a(described_class))
    expect(error.message).to(
      eq(
        "isolated baseline is not green: the unmutated suite fails in a mirror of the project\n  " \
          "E: x\n      at a.rb:1\n  hint"
      )
    )
  end

  it "prints the survivor panel framing exactly" do
    io = StringIO.new
    panel = Kimera::CLI::Survivors::Panel.new(io: io)
    row = {
      "mutant_id" => 7, "file" => "b.rb", "line" => 4, "label" => "x",
      "original" => "a", "mutated" => "b", "covering_tests" => ["t"]
    }
    panel.announce([["b.rb", 4, row]], status: "survived", report: "report.json")

    expect(io.string).to(
      eq(
        "1 survived mutant(s):\n\n  #7  b.rb:4  [x]\n    - a\n    + b\n    " \
          "covered by 1 test(s)\n\ndetail: kimera mutant <ID|KEY> --report report.json\n"
      )
    )
  end

  it "records only the first killing test in the attempt memory" do
    passed = Struct.new(:passed?).new(true)
    killed = Struct.new(:passed?).new(false)
    adapter = Object.new
    adapter.define_singleton_method(:run) { |ids| ids == ["a"] || Kimera::Runtime.active.nil? ? passed : killed }
    isolation = Object.new
    isolation.define_singleton_method(:around) { |&block| block.call }
    remembered = []
    killers = Object.new
    killers.define_singleton_method(:order) { |tests| tests }
    killers.define_singleton_method(:remember) { |id| remembered << id }
    attempt = Kimera::Execution::Shift::Attempt.new(
      adapter: adapter, isolation: isolation, killers: killers, deadline: Kimera::Execution::Shift::Deadline.new(nil)
    )

    expect(attempt.run(9, %w[a b c])).to(equal(killed))
    expect(remembered).to(eq(["b"]))
  end

  it "emits the complete coverage-channel protocol and closes its runtime ledger" do
    outcome = Struct.new(:passed?, :failures).new(false, { "t" => "boom" })
    adapter = Object.new
    adapter.define_singleton_method(:run) do |_ids|
      Kimera::Runtime.active?(7)
      outcome
    end
    request = StringIO.new("{\"id\":\"t\"}\n")
    response = StringIO.new
    before = Array(Kimera::Runtime.instance_variable_get(:@ledgers)).size

    Kimera::Execution::Shift::CoverageChannel.new(adapter).serve(request, response)

    messages = response.string.lines.map { |line| JSON.parse(line) }
    expect(messages.first.except("touched", "took")).to(
      eq(
        "t" => "result", "id" => "t", "passed" => false, "failure" => "boom"
      )
    )
    expect(messages.first.fetch("touched")).to(include(7))
    expect(messages.drop(1)).to(eq([{ "t" => "ready" }, { "t" => "done" }]))
    expect(Array(Kimera::Runtime.instance_variable_get(:@ledgers)).size).to(eq(before))
  ensure
    Kimera::Runtime.reset!
  end

  it "observes every leak-guard branch and its exact event" do
    io = StringIO.new
    calls = []
    outcomes = [Struct.new(:killed?).new(true), Struct.new(:killed?).new(false)]
    guard =
      Kimera::Execution::Shift::LeakGuard.new(2) do |id|
        calls << id
        outcomes.shift
      end

    [[[3], 0], [[], 1], [[3], 1], [[4], 3]].each { |arguments| guard.check(io, *arguments) }

    expect(calls).to(eq([3, 4]))
    expect(io.string.lines.map { |line| JSON.parse(line) }).to(
      eq(
        [
          {
            "t" => "leak", "id" => 4,
            "detail" => "mutant 4 killed earlier but survived re-run (state leakage suspected)"
          }
        ]
      )
    )
  end

  it "disables leak checks when no interval is configured" do
    guard = Kimera::Execution::Shift::LeakGuard.new(nil) { raise(RuntimeError, "must not run") }
    expect { guard.check(StringIO.new, [1], 0) }.not_to(raise_error)
  end

  it "matches callback values only by their supported identity protocol" do
    value = Struct.new(:attributes)
    plain = Class.new

    expect(Kimera::Execution::Callback.new(value.new({ x: 1 })).duplicate?(value.new({ x: 1 }))).to(be(true))
    expect(Kimera::Execution::Callback.new(value.new({ x: 1 })).duplicate?(value.new({ x: 2 }))).to(be(false))
    expect(Kimera::Execution::Callback.new(value.new({ x: 1 })).duplicate?(plain.new)).to(be(false))
    expect(Kimera::Execution::Callback.new(plain.new).duplicate?(plain.new)).to(be(true))
  end

  it "serializes the worker result protocol exactly" do
    result = Kimera::MutantResult.new(
      mutant_id: 8, status: :killed, duration: 1.5,
      failing_tests: ["a"], covering_tests: %w[a b]
    )
    expect(result.message).to(
      eq(t: "result", id: 8, status: "killed", ms: 1.5, fails: ["a"], cover: %w[a b], detail: nil)
    )
  end

  it "requires a location to lie inside a method span, ending no later than it (endless defs)" do
    location = Kimera::Location.new(start_offset: 11, span: 4)
    expect(location.within?(10, 20)).to(be(true))
    expect(Kimera::Location.new(start_offset: 9, span: 4).within?(10, 20)).to(be(false))
    expect(Kimera::Location.new(start_offset: 19, span: 4).within?(10, 20)).to(be(false))
    expect(Kimera::Location.new(start_offset: 16, span: 4).within?(10, 20)).to(be(true))
    expect(Kimera::Location.new(start_offset: 10, span: 4).within?(10, 20)).to(be(false))
  end

  it "loads configured plugins before constructing the run cycle" do
    runner = Kimera::CLI::Run.new
    options = { require: ["plugin.rb"], source_root: "/project", since: "main" }
    registry = Object.new
    sources = instance_double(Kimera::CLI::Run::Sources, load: registry)
    allow(Kimera::CLI::Run::Sources).to(receive(:new).and_return(sources))
    allow(Kimera::CLI::Run::Sources).to(receive(:changed).with(options).and_return(["a.rb"]))
    allow(Kimera::Plugins).to(receive(:load!).and_return([]))

    cycle = runner.__send__(:cycle, options)
    expect(cycle).to(be_a(Kimera::CLI::Run::Cycle))
    expect(runner.__send__(:cycle, options.merge(since: nil))).to(be_a(Kimera::CLI::Run::Cycle))
    expect(runner.__send__(:digest)).to(be_a(Kimera::CLI::Run::Digest))
    expect(Kimera::Plugins).to(have_received(:load!).with(["plugin.rb"], root: "/project").twice)
    expect(Kimera::CLI::Run::Sources).to(have_received(:changed).with(options).once)
  end

  it "builds the isolated runner contract without lossy intermediate hashes" do
    registry = Object.new
    adapter = instance_double(Kimera::Frameworks::Adapter, test_ids: %w[t1 t2])
    options = {
      source_root: "/root", jobs: 3, framework: "rspec", hard_timeout: 9,
      progress: false, tests: [], exclude_tests: []
    }
    pass = Kimera::CLI::Run::Pass.new(registry, options, adapter)
    harness = instance_double(Kimera::Execution::Harness, coverage: { 1 => ["t1"] })
    pass.instance_variable_set(:@_harness, harness)
    pass.instance_variable_set(:@_files, ["a_spec.rb"])

    expect(pass.__send__(:core)).to(
      eq(
        registry: registry, root: "/root", tests: %w[t1 t2], coverage: { 1 => ["t1"] },
        progress: pass.__send__(:progress), jobs: 3, framework: "rspec", test_files: ["a_spec.rb"]
    )
    )
  end

  it "routes harness-critical mutants to fresh-process evaluation" do
    registry = Kimera::RegistryScan.new.source(
      "def call\n  true\nend\n", file: "lib/kimera/execution/harness.rb"
    )
    id = registry.each.first.first.id
    pass = Kimera::CLI::Run::Pass.new(registry, { isolate_when_covered_by: [] }, Object.new)
    pass.instance_variable_set(:@_harness, instance_double(Kimera::Execution::Harness, coverage: {}))

    expect(pass.__send__(:split, [id])).to(eq([[id], []]))
  end

  it "routes boot failures to the injected error stream" do
    errors = StringIO.new
    application = Object.new
    application.define_singleton_method(:eager_load!) { raise RuntimeError, "broken" }
    stub_const("Rails", Module.new)
    Rails.define_singleton_method(:application) { application }

    Kimera::Execution::Boot.new(adapter: Object.new, isolate: false, errors: errors).load!
    expect(errors.string).to(
      eq(
      "kimera: eager_load! failed (RuntimeError: broken); lazily-autoloaded files may escape mutation\n"
    )
    )
  end

  it "owns and closes the reload result reader" do
    reader, writer = IO.pipe
    errand = Kimera::Execution::Reload::Errand.new(1, [], reader, writer)
    writer.puts("result")
    writer.close

    expect(errand.await(0.1) { raise(RuntimeError, "unexpected timeout") }).to(eq("result\n"))
    expect(reader).to(be_closed)
  ensure
    reader&.close unless reader&.closed?
    writer&.close unless writer&.closed?
  end

  it "serializes a reload verdict at its process boundary", :aggregate_failures do
    reload = Kimera::Execution::Reload.allocate
    errand = Kimera::Execution::Reload::Errand.new(7, [], nil, nil)
    allow(reload).to(receive(:evaluate).with(errand).and_return([:killed, ["t1"]], [:unmutatable, [], "why"]))
    expect(JSON.parse(reload.__send__(:report, errand)))
      .to(eq("id" => 7, "status" => "killed", "fails" => ["t1"], "detail" => nil))
    expect(JSON.parse(reload.__send__(:report, errand)))
      .to(eq("id" => 7, "status" => "unmutatable", "fails" => [], "detail" => "why"))
  end

  it "prunes leak records whose mutant result is absent" do
    result = ->(id) { Kimera::MutantResult.new(mutant_id: id, status: :killed) }
    leaks = [1, 2].map { |id| Kimera::LeakReport.new(mutant_id: id, detail: id.to_s) }
    session = Kimera::Incremental::Session.new(results: { 1 => result.call(1), 2 => result.call(2) }, leaks: leaks)
    allow(session).to(receive(:stale?) { |id, _registry| id == 2 })

    session.prune!(Object.new)
    expect(session.results.keys).to(eq([1]))
    expect(session.leaks.map(&:mutant_id)).to(eq([1]))
  end

  it "describes missing, signaled, and exited worker statuses" do
    guard = Kimera::Execution::WorkerPool::StillbornGuard.new(1)
    exited = Struct.new(:signaled?, :exitstatus).new(false, 3)
    signaled = Struct.new(:signaled?, :termsig).new(true, 9)

    expect(guard.__send__(:describe, nil)).to(eq("unknown"))
    expect(guard.__send__(:describe, exited)).to(eq("status 3"))
    expect(guard.__send__(:describe, signaled)).to(eq("signal 9"))

    expect { guard.track(exited) }.not_to(raise_error)
    expect { guard.track(exited) }.to(raise_error(Kimera::Error, /2 warm workers died.*last exit: status 3/m))
    progressed = Kimera::Execution::WorkerPool::StillbornGuard.new(1)
    progressed.progress!
    expect { 3.times { progressed.track(exited) } }.not_to(raise_error)
  end
end
