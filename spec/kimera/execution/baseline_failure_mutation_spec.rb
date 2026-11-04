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
require "kimera/registry/builder"
require "kimera/registry/mutation_point"
require "kimera/results/result"
require "stringio"
require "tmpdir"

RSpec.describe(Kimera::Execution::BaselineFailure, :aggregate_failures) do
  describe "the baseline summary" do
    def summary = Kimera::Execution::BaselineFailure::Summary

    it "renders every failed test, multi-line and over-long messages, and the plain command" do
      limit = summary::MAX_MESSAGE
      messages = { "a" => "one\ntwo", "b" => "x" * (limit + 1), "c" => nil }
      expect(summary.new(%w[a b c d], messages, "rspec a b c --order defined").to_s).to(
        eq(
          "baseline suite is not green: 4 tests failed:\n    a\n    b\n    c\n    d\n  " \
            "a:\n    one\n    two\n  " \
            "b:\n    #{"x" * limit}…\n  " \
            "reproduce without kimera: rspec a b c --order defined"
        )
      )
    end

    it "names a single failed test on its headline" do
      expect(summary.new(["a"], {}, "ruby -n a").to_s).to(
        eq("baseline suite is not green: a\n  reproduce without kimera: ruby -n a")
      )
    end

    it "keeps a message exactly at the limit whole" do
      limit = summary::MAX_MESSAGE
      expect(summary.new(["a"], { "a" => "y" * limit }, "c").to_s).to(include("    #{"y" * limit}\n"))
    end
  end

  it "breaks a red parallel baseline down per worker, in the order each ran its tests" do
    workers = { 1 => %w[p q r s t u v x1 x2 x3 x4 x5], 0 => %w[a b], 2 => %w[c] }
    failed = %w[s u c x1 x2 x3 x4 x5]

    summary = Kimera::Execution::BaselineFailure::Summary
    context = summary::Context.new(workers: workers, stacks: {}, jobs: 1, ordered: [])
    expect(summary.new(failed, {}, "cmd", context).to_s).to(
      eq(
        "baseline suite is not green: 8 tests failed:\n    #{failed.join("\n    ")}\n  " \
          "per worker (tests in the order it ran them):\n    " \
          "worker 1: ran 12; failed #4 s, #6 u, #8 x1, #9 x2, #10 x3 (+2 more); just before: p, q, r\n    " \
          "worker 2: ran 1; failed #1 c (first test on this worker)\n  " \
          "reproduce without kimera: cmd"
      )
    )
  end

  it "renders a red isolated baseline with its reason indented and the mirror hint" do
    mirror = Kimera::Execution::BaselineFailure::Mirror.new("E: x\n  at a.rb:1", "  hint")
    expect(mirror.to_s).to(
      eq(
        "isolated baseline is not green: the unmutated suite fails in a mirror of the project\n  " \
          "E: x\n      at a.rb:1\n  hint"
      )
    )
  end

  it "prints the survivor panel framing exactly" do
    io = StringIO.new
    row = {
      "mutant_id" => 7, "file" => "b.rb", "line" => 4, "label" => "x",
      "original" => "a", "mutated" => "b", "covering_tests" => ["t"]
    }
    selection = Kimera::CLI::Survivors::Selection.new("survived", nil, "report.json", false)
    io.puts(*Kimera::CLI::Survivors::Panel.new.announce([["b.rb", 4, row]], selection))

    expect(io.string).to(
      eq(
        "1 survived mutant(s):\n\n  #7  b.rb:4  [x]\n    - a\n    + b\n    " \
          "covered by 1 test(s)\n\ndetail: kimera mutant <ID|KEY> --report report.json\n"
      )
    )
  end

  describe "an attempt" do
    # Passes test "a", and any test while no mutant is active; fails the rest.
    def picky
      passed = Kimera::Frameworks::RunOutcome.new(passed: true, failed_ids: [])
      Object.new.tap do |adapter|
        adapter.define_singleton_method(:run) do |ids|
          next passed if ids == ["a"] || Kimera::RUNTIME.active.nil?
          Kimera::Frameworks::RunOutcome.new(passed: false, failed_ids: ids, failures: { ids.first => "boom" })
        end
      end
    end

    def attempt
      isolation = Object.new.tap { |inline| inline.define_singleton_method(:around) { |&block| block.call } }
      probe = Kimera::Execution::Shift::Probe.new(picky, Kimera::Execution::Shift::Deadline.build(nil))
      Kimera::Execution::Shift::Attempt.new(probe: probe, isolation: isolation, zygote: InlineZygote.new)
    end

    def memory = Kimera::Execution::Shift::KillerMemory.new

    it "stops at the first killing test" do
      subject = Kimera::Execution::Shift::Subject.new(9, "x.rb")
      verdicts, = attempt.run(9, %w[a b c], memory)
      expect(verdicts.map { |verdict| verdict.ruling(subject, {}) })
        .to(match([have_attributes(status: :killed, failing_tests: ["b"], detail: "boom")]))
    end

    it "records only the first killing test in the attempt memory" do
      _, known = attempt.run(9, %w[a b c], memory)
      expect(known.order(%w[c a b])).to(eq(%w[b c a]))
    end
  end

  describe "the coverage channel" do
    # Its one test, "t", reaches mutant 7 and fails with "boom".
    def reaching
      Object.new.tap do |adapter|
        adapter.define_singleton_method(:run) do |_ids|
          Kimera::RUNTIME.active?(7)
          Struct.new(:passed?, :failures).new(false, { "t" => "boom" })
        end
      end
    end

    def served
      response = StringIO.new
      channel = Kimera::Execution::Shift::CoverageChannel.new(reaching, zygote: InlineZygote.new)
      channel.serve(StringIO.new("{\"id\":\"t\"}\n"), response)
      response.string.lines.map { |line| JSON.parse(line) }
    end

    def ledgers = Array(Kimera::RUNTIME.instance_variable_get(:@ledgers)).size

    it "reports the test's result and what it touched" do
      result = served.first
      expect(result.except("touched", "took"))
        .to(eq("t" => "result", "id" => "t", "passed" => false, "failure" => "boom"))
      expect(result.fetch("touched")).to(include(7))
    end

    it "says it is ready, then done" do
      expect(served.drop(1)).to(eq([{ "t" => "ready" }, { "t" => "done" }]))
    end

    it "closes its runtime ledger" do
      open = ledgers
      served
      expect(ledgers).to(eq(open))
    end
  end

  describe "callback identity" do
    let(:value) { Struct.new(:attributes) }

    def duplicate?(kept, candidate) = Kimera::Execution::Callback.new(kept).duplicate?(candidate)

    it "matches attribute values by their attributes" do
      kept = value.new({ x: 1 })
      expect([duplicate?(kept, value.new({ x: 1 })), duplicate?(kept, value.new({ x: 2 }))]).to(eq([true, false]))
    end

    it "never matches another kind of object to an attribute value" do
      expect(duplicate?(value.new({ x: 1 }), Class.new.new)).to(be(false))
    end

    it "matches plain objects of one class" do
      plain = Class.new
      expect(duplicate?(plain.new, plain.new)).to(be(true))
    end
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
    method = Struct.new(:start_offset, :end_offset).new(10, 20)
    within = [11, 9, 19, 16, 10].map { |start| Kimera::Location.new(start_offset: start, span: 4).within?([method]) }
    expect(within).to(eq([true, false, false, true, false]))
  end

  describe "the run cycle's setup" do
    around { |example| Dir.mktmpdir { |dir| Dir.chdir(dir) { example.run } } }

    before do
      File.write("a.rb", "def a(x)\n  x > 1\nend\n")
      File.write("b.rb", "def b(x)\n  x < 1\nend\n")
      FileUtils.mkdir_p("spec")
      File.write("spec/a_spec.rb", "")
      File.write("plugin.rb", "File.write(File.join(__dir__, \"plugged\"), \"\")\n")
    end

    # The mutants the warm harness ran in a run of a.rb and b.rb with +flags+,
    # where a --since run finds line 2 of a.rb changed.
    def ran(*flags)
      harness = FakeHarness.new
      bench = FakeBench.new(harness: harness, changed: { "a.rb" => Set[2] })
      Kimera::CLI::Run.new(io: StringIO.new, errors: StringIO.new, bench: bench)
        .run(["a.rb", "b.rb", "--no-report", *flags])
      harness.asked.filter_map { |kind, ids| ids if kind == :run }.flatten
    end

    # a.rb and b.rb each hold the same number of mutants, all on line 2.
    it "narrows the run to the lines changed since the reference, and runs everything without one" do
      narrowed = ran("--since", "main")
      expect([narrowed.size * 2, narrowed.empty?]).to(eq([ran.size, false]))
    end

    it "loads the configured plugins from the source root" do
      ran("--require", "plugin.rb")
      expect(File).to(exist("plugged"))
    end

    it "builds a digest" do
      expect(Kimera::CLI::Run.new.__send__(:digest)).to(be_a(Kimera::CLI::Run::Digest))
    end
  end

  describe "the isolated runner contract" do
    let(:registry) { Object.new }
    let(:adapter) { FakeSuite.new(%w[t1 t2], files: { "t1" => "spec/t1_spec.rb" }) }
    let(:harness) { FakeHarness.new }
    let(:pass) do
      options = {
        source_root: "/root", jobs: 3, framework: "rspec", hard_timeout: 9,
        progress: false, tests: [], exclude_tests: []
      }
      Kimera::CLI::Run::Pass.new(registry, options, adapter, FakeBench.new(harness: harness)).tap do |pass|
        pass.instance_variable_set(:@_files, ["a_spec.rb"])
      end
    end

    it "is handed to the harness without lossy intermediate hashes" do
      expect(pass.__send__(:isolation).settings).to(
        match(
          registry: registry, root: "/root", tests: %w[t1 t2],
          progress: pass.__send__(:progress), jobs: 3, framework: "rspec", test_files: ["a_spec.rb"],
          filter: pass.__send__(:filter), test_paths: an_instance_of(Proc), warnings: [], hard_timeout: 9
        )
      )
    end

    it "gets the warm pass's coverage and timings from the harness" do
      warm = Kimera::Execution::Harness.build(
        registry: registry, adapter: adapter, coverage: { 1 => ["t1"] }, timings: { "t1" => 0.5 }
      )
      expect(warm.survey.isolated(FakeExecutions.new, registry: registry, jobs: 3))
        .to(eq(coverage: { 1 => ["t1"] }, timings: { "t1" => 0.5 }, registry: registry, jobs: 3))
    end

    # R6B3-M1: a Minitest suite's mirrors run with the warnings its Rakefile's test task sets.
    def warnings(framework)
      Dir.mktmpdir do |root|
        File.write(File.join(root, "Rakefile"), "Rake::TestTask.new\n")
        options = { source_root: root, framework: framework, progress: false, tests: [], exclude_tests: [] }
        Kimera::CLI::Run::Pass.new(registry, options, adapter).__send__(:warnings)
      end
    end

    it "hands a Minitest run the ruby -w its Rakefile's test task sets, an RSpec run none", :aggregate_failures do
      expect(warnings("minitest")).to(eq(["-w"]))
      expect(warnings("rspec")).to(eq([]))
    end

    it "finds each test's file through the suite" do
      expect(pass.__send__(:core).fetch(:test_paths).call("t1")).to(eq("spec/t1_spec.rb"))
    end
  end

  it "routes harness-critical mutants to fresh-process evaluation" do
    registry = Kimera::RegistryScan.new.source(
      "def call\n  true\nend\n", file: "lib/kimera/execution/harness.rb"
    )
    id = registry.each.first.first.to_i
    route = Kimera::CLI::Run::Route.new(registry, { isolate_when_covered_by: [] })

    expect(route.split([id]) { {} }).to(eq([[id], []]))
  end

  it "routes boot failures to the injected error stream" do
    errors = StringIO.new
    application = Object.new.tap { |app| app.define_singleton_method(:eager_load!) { raise RuntimeError, "broken" } }
    stub_const("Rails", Module.new.tap { |rails| rails.define_singleton_method(:application) { application } })
    Kimera::Execution::Boot.new(adapter: Object.new, isolate: false, errors: errors).load!
    expect(errors.string).to(
      eq("kimera: eager_load! failed (RuntimeError: broken); lazily-autoloaded files may escape mutation\n")
    )
  end

  def awaited(reader, writer)
    writer.tap { |sink| sink.puts("result") }.close
    Kimera::Execution::Reload::Errand.new(1, [], reader, writer).await(0.1) { raise(RuntimeError, "unexpected timeout") }
  end

  it "owns and closes the reload result reader" do
    IO.pipe do |reader, writer|
      expect(awaited(reader, writer)).to(eq("result\n"))
      expect(reader).to(be_closed)
    end
  end

  it "serializes a reload verdict at its process boundary", :aggregate_failures do
    verdicts = [[:killed, ["t1"]], [:unmutatable, [], "why"]]
    reload = Class.new(Kimera::Execution::Reload) { define_method(:evaluate) { |*| verdicts.shift } }.allocate
    errand = Kimera::Execution::Reload::Errand.new(7, [], nil, nil)
    expect(JSON.parse(reload.__send__(:report, 7, errand)))
      .to(match("id" => 7, "status" => "killed", "fails" => ["t1"], "detail" => nil, "ms" => Float, "cover" => []))
    expect(JSON.parse(reload.__send__(:report, 7, errand)))
      .to(match("id" => 7, "status" => "unmutatable", "fails" => [], "detail" => "why", "ms" => Float, "cover" => []))
  end

  # Mutant 1 of the registry, and 999, which it no longer has: the session saved a result and a leak for each.
  describe "a session's pruning" do
    let(:registry) { Kimera::RegistryScan.new.source("def m(a, b)\n  a > b\nend\n", file: "calc.rb") }
    let(:kept) { registry.each.first.first.to_i }
    let(:session) do
      result = ->(id) { Kimera::MutantResult.new(mutant_id: id, status: :killed) }
      leaks = [kept, 999].map { |id| Kimera::LeakReport.new(mutant_id: id, detail: id.to_s) }
      results = { kept => result.call(kept), 999 => result.call(999) }
      Dir.mktmpdir do |dir|
        path = File.join(dir, "session.json")
        Kimera::Incremental::Session.new(results: results, leaks: leaks).save(path, registry)
        Kimera::Incremental::Session.from(path)
      end
    end

    # The mutants a session holds results for, and those its leaks name.
    def held(session)
      report = session.report([kept, 999], [], registry)
      [report.results.map(&:mutant_id), report.leaks.map(&:mutant_id)]
    end

    it "drops stale results and the leak records whose result is gone" do
      expect(held(session.pruned(registry))).to(eq([[kept], [kept]]))
    end

    it "leaves the session itself whole" do
      session.pruned(registry)
      expect(held(session).first).to(eq([kept, 999]))
    end
  end

  describe "the stillborn guard" do
    let(:exited) { Struct.new(:signaled?, :exitstatus).new(false, 3) }

    def guard = Kimera::Execution::WorkerPool::StillbornGuard.new(1)

    it "describes missing, signaled, and exited worker statuses" do
      signaled = Struct.new(:signaled?, :termsig).new(true, 9)
      described = [nil, exited, signaled].map { |status| guard.__send__(:describe, status) }
      expect(described).to(eq(["unknown", "status 3", "signal 9"]))
    end

    it "tolerates one stillborn worker, and raises at the next" do
      watch = guard
      expect { watch.track(exited) }.not_to(raise_error)
      expect { watch.track(exited) }.to(raise_error(Kimera::Error, /2 warm workers died.*last exit: status 3/m))
    end

    it "tolerates any number once a worker made progress" do
      progressed = guard.tap(&:progress!)
      expect { 3.times { progressed.track(exited) } }.not_to(raise_error)
    end
  end
end
