# frozen_string_literal: true

require "kimera/audit/operator_audit"
require "kimera/cli/baseline"
require "kimera/cli/mutant"
require "kimera/cli/run/pass"
require "fileutils"
require "kimera/execution/child_process"
require "kimera/execution/harness"
require "kimera/execution/worker_databases"
require "kimera/execution/pool_driver"
require "kimera/execution/reload"
require "kimera/operators/node_swap"
require "kimera/rewrite/directive"
require "kimera/parsing/syntax_types"
require "kimera/synthesis/file_weave"
require "json"
require "stringio"
require "timeout"
require "tmpdir"

RSpec.describe Kimera::Execution, :aggregate_failures do
  let(:errors) { StringIO.new }

  def malformation(input)
    JSON.parse(input)
  rescue JSON::ParserError => error
    error.message
  end

  it "falls back to the original source when audit reprinting fails" do
    rendering = Kimera::Operators::Audit::Rendering.new("def (", "rendered")

    expect(rendering.__send__(:reprinted)).to(eq("def ("))
    expect(rendering.verdict).to(eq(Kimera::Operators::Audit::OK))
  end

  describe "a malformed report" do
    let(:dir) { Dir.mktmpdir }

    after { FileUtils.remove_entry(dir) }

    def broken = File.join(dir, "broken.json").tap { |path| File.write(path, "{") }

    def mutant(*argv) = Kimera::CLI::Mutant.new(io: StringIO.new, errors: errors).run(argv)

    it "is explained with the parser's detail when creating a baseline" do
      argv = ["create", broken, "--reason", "legacy", "--output", File.join(dir, "baseline.yml")]
      status = Dir.chdir(dir) { Kimera::CLI::Baseline.new(errors: errors).run(argv) }
      expect(status).to(eq(1))
      expect(errors.string).to(include("unreadable report #{broken}", malformation("{")))
    end

    it "is explained with the parser's detail on a rerun" do
      expect(mutant("1", "--report", broken, "--rerun")).to(eq(1))
      expect(errors.string).to(include("unreadable report #{broken}", malformation("{")))
    end

    it "is not needed to reject an unknown mutant ID" do
      listed = File.join(dir, "listed.json")
      File.write(listed, JSON.generate("results" => [{ "mutant_id" => 1, "status" => "killed" }]))
      expect(mutant("not-an-id", "--report", listed)).to(eq(1))
      expect(errors.string).to(include("no mutant #not-an-id in this report"))
    end
  end

  it "matches string-keyed coverage entries" do
    route = Kimera::CLI::Run::Route.new(nil, {})
    expect(route.__send__(:matches?, { "7" => ["spec/critical_spec.rb"] }, 7, "critical")).to(be(true))
  end

  def silenced_output
    IO.popen("-") do |pipe|
      next pipe.read if pipe
      IO.for_fd(2, autoclose: false).reopen(IO.for_fd(1, autoclose: false))
      $stdout.print("before|")
      $stdout.flush
      Class.new { include Kimera::Execution::ChildProcess }.new.__send__(:silence!)
      $stdout.print("ruby out")
      $stderr.print("ruby err")
      system("echo shell out; echo shell err >&2")
      exit!(0)
    end
  end

  it "points the child's descriptors 1 and 2, and Ruby's streams, at the null device" do
    expect(silenced_output).to(eq("before|"))
  end

  it "exposes the harness skip map and hands the rig the spawner it was given" do
    token = Object.new
    harness = Kimera::Execution::Harness.build(registry: Object.new, adapter: Object.new, spawner: token)

    expect(harness.skipped).to(eq({}))
    expect(harness.__send__(:spawner)).to(equal(token))
  end

  describe "worker databases" do
    let(:databases) { Kimera::Execution::WorkerDatabases.new(jobs: 2, errors: errors) }

    def unavailable
      "kimera: per-worker test databases unavailable (LoadError: missing helper); workers share one database\n"
    end

    # Rails' parallel testing, whose registration file raises +loading+ when given.
    def parallelization(loading = nil)
      par = Module.new
      par.define_singleton_method(:after_fork_hooks) { [->(_index) {}] }
      par.define_singleton_method(:run_cleanup_hooks) { [->(_index) { raise(RuntimeError, "teardown boom") }] }
      stub_const("ActiveSupport::Testing::Parallelization", par)
      fake_feature("active_record/test_databases", loading ? "raise(#{loading})" : "")
    end

    it "report teardown failures with the injected error stream" do
      parallelization
      databases.before_exit(1)
      expect(errors.string).to(eq("kimera: parallelize_teardown failed (RuntimeError: teardown boom)\n"))
    end

    it "report to standard error by default" do
      parallelization
      expect { Kimera::Execution::WorkerDatabases.new(jobs: 2).before_exit(1) }
        .to(output("kimera: parallelize_teardown failed (RuntimeError: teardown boom)\n").to_stderr)
    end

    it "report unavailable per-worker database support with exception detail" do
      stub_const("ActiveRecord::Base", Class.new)
      parallelization('LoadError, "missing helper"')
      databases.__send__(:register!)
      expect(errors.string).to(eq(unavailable))
    end
  end

  def pool(database: FakeDatabases.new)
    Kimera::Execution::Pool.new(
      adapter: Object.new, registry: Object.new, isolation: Object.new,
      coverage: {}, paralleldb: database, soft: 1.0, hard: 2.0, leak: 3, jobs: 1
    )
  end

  describe "a pool duty" do
    let(:shift) { FakeShift.new }
    let(:database) { FakeDatabases.new }
    let(:response) { IO.pipe }

    def served
      pipes = Kimera::Execution::Pool::Channels.new(:request, nil, nil, response.last)
      Kimera::Execution::Pool::Duty.new(:coverage, 4, pipes).tap do |duty|
        duty.run(shift)
        duty.finish(database, nil)
      end
    end

    it "serves its errand through the shift" do
      served
      expect(shift.served).to(eq([[:coverage, :request, response.last]]))
    end

    it "tells the databases its worker exits" do
      served
      expect(database.exited).to(eq([4]))
    end

    it "closes its response pipe without writing to it" do
      served
      expect([response.last.closed?, response.first.read]).to(eq([true, ""]))
    end
  end

  # Read in the parent, what a duty wrote down in the worker the block forks.
  def noted(notes)
    reader, writer = notes
    pid = yield
    writer.close
    [reader.readlines(chomp: true).map { |line| JSON.parse(line) }, Process.wait2(pid).last.exitstatus]
  end

  describe "a pool child's boot" do
    let(:database) { FakeDatabases.new }
    let(:notes) { IO.pipe }
    let(:duty) { FakeDuty.new(5, notes.last) }

    # Boots worker 5 in a fork that exits 1 unless the boot exits first.
    def booted
      runner = pool(database: database)
      noted(notes) do
        fork do
          runner.__send__(:boot, duty)
        ensure
          exit!(1)
        end
      end
    end

    it "takes the child's pipe ends and silences it" do
      seen = nil
      expect([descriptor_one { seen = booted }, seen.first.first.last(2)]).to(eq(["", [true, true]]))
    end

    it "gives the worker its database, runs the duty through a shift and always retires it" do
      notes, = booted
      expect(notes).to(eq([["run", "Kimera::Execution::Shift", false, true, true], ["retire", [5], nil, nil]]))
    end

    it "exits cleanly" do
      expect(booted.last).to(eq(0))
    end

    it "builds a shift for the duty" do
      expect(pool.__send__(:build, duty)).to(be_a(Kimera::Execution::Shift))
    end

    # R4-KR1: a parallelize_setup hook raised before the worker could say a word.
    def unprepared(database)
      said = StringIO.new
      pool(database: database).__send__(:serve, FakeDuty.new(5, said))
    rescue Kimera::Execution::Pool::Unprepared => error
      [error, said.string.lines.map { |line| JSON.parse(line) }]
    end

    it "retires a worker whose after-fork setup raised with what it raised", :aggregate_failures do
      raised, notes = unprepared(FakeDatabases.new { raise(RuntimeError, "search index unavailable") })
      expect(raised.headline).to(eq("worker 5's after-fork setup raised RuntimeError: search index unavailable"))
      expect(notes).to(eq([["retire", [5], "Kimera::Execution::Pool::Unprepared", raised.message]]))
    end

    it "keeps the setup error's backtrace" do
      raised, = unprepared(FakeDatabases.new { raise(ScriptError, "x") })
      expect(raised.backtrace.first).to(include(__FILE__))
    end
  end

  # The hard watchdog renews on each test's beat, so a slow test's raised soft
  # limit stays a second under it and the soft timeout still fires first.
  it "keeps a test's raised soft limit under the hard watchdog" do
    patience = Kimera::Execution::Patience.new(0.1, timings: { "t" => 5.0 }, hard: pool.__send__(:hard))
    expect(patience.limit("t")).to(eq(1.0))
  end

  it "hands the shift a pulse that ticks through the worker's duty" do
    said = StringIO.new
    pool.__send__(:pulse, FakeDuty.new(1, said)).call
    expect(said.string).to(eq("[\"pulse\"]\n"))
  end

  # Leading its own process group, the worker takes what its tests start
  # down with it when it is killed.
  it "boots a pool duty inside the fork block, as the leader of a process group" do
    notes = IO.pipe
    seen, status = noted(notes) { pool.__send__(:spawn, FakeDuty.new(5, notes.last)) }
    expect([seen.first.take(3), status]).to(eq([["run", "Kimera::Execution::Shift", true], 0]))
  end

  describe "a reload errand" do
    # An errand on a real pipe, emitted from the child's side: which ends it closed, and what a second
    # copy of the parent's end reads.
    def emitted
      reader, writer = IO.pipe
      kept = reader.dup
      Kimera::Execution::Reload::Errand.new(8, [], reader, writer).tap(&:child!).emit("payload")
      [reader.closed?, writer.closed?, kept.read]
    end

    it "closes the parent's end in the child, writes its payload and closes its own end" do
      expect(emitted).to(eq([true, true, "payload\n"]))
    end

    it "flushes each tick straight to the parent" do
      IO.pipe do |parent, child|
        Kimera::Execution::Reload::Errand.new(8, [], IO.pipe.first, child).tap(&:child!).tick("t1")
        expect(parent.read_nonblock(16)).to(eq("tick\n"))
      end
    end
  end

  describe "a reload worker" do
    let(:reload) do
      Kimera::Execution::Reload.new(registry: Object.new, adapter: Object.new, isolation: Object.new, workspace: nil)
    end

    # An errand on a real pipe whose child side first says whether the child leads its own process group,
    # and prints to standard output before it emits, as tests do.
    let(:errand) do
      Class.new(Kimera::Execution::Reload::Errand) do
        def child!
          super
          writer.puts(Process.getpgrp == Process.pid ? "leader" : "member")
        end

        def emit(payload)
          $stdout.print("loud")
          $stdout.flush
          super
        end
      end.new(9, [], *IO.pipe)
    end

    # The reload child of the errand: whether the parent's writer is closed, what the child wrote (until the
    # pipe closes, or 10 s), and how it exited.
    def worked
      pid = reload.__send__(:child, errand)
      said = Timeout.timeout(10) { errand.reader.readlines(chomp: true) }
      [errand.writer.closed?, said, Process.wait2(pid).last.exitstatus]
    end

    it "leads its process group before it takes the child's pipe ends" do
      expect(worked[1].first).to(eq("leader"))
    end

    it "silences the child and emits the report on its errand" do
      lines = nil
      expect(descriptor_one { _, lines, = worked }).to(eq(""))
      expect(JSON.parse(lines.last)).to(include("id" => 9, "status" => "error"))
    end

    it "exits cleanly" do
      expect(worked.last).to(eq(0))
    end

    # The child leads its own process group, so the terminal's Ctrl-C never
    # reaches it: an interrupted kimera kills and reaps it on the way out.
    it "takes a reload child down with it when kimera is interrupted" do
      pid = fork { sleep(300) }
      interrupted = Class.new(Kimera::Execution::Reload::Errand) { def await(_deadline, &) = raise(Interrupt) }.new
      expect { Timeout.timeout(10) { reload.__send__(:hear, interrupted, pid, 1.0) } }.to(raise_error(Interrupt))
      expect { Process.kill(0, pid) }.to(raise_error(Errno::ESRCH))
    end

    it "runs inside the fork block before closing the parent writer" do
      expect(worked.first).to(be(true))
    end
  end

  it "swaps a node by its class into the mutation the subclass names" do
    operator = Kimera::Operators::BooleanLiteral.new
    node = Kimera::Syntax.parse("true").value.statements.body.first

    expect(operator.key).to(eq("boolean_literal"))
    expect(operator.variants(node).map(&:label)).to(eq(["true => false"]))
  end

  it "builds frozen directive lookup tables from alternating entries" do
    table = Kimera::Rewrite::Directive::TABLE.call("one", :first, "two", :second)
    expect(table).to(eq("one" => :first, "two" => :second))
    expect(table).to(be_frozen)
  end

  describe "the syntax type installer" do
    def node_name = Kimera::SyntaxTypes.constants.grep(/Node\z/).first

    it "installs each syntax node constant" do
      target = Module.new.tap { |space| Kimera::SyntaxTypes::Import.new(space).call }
      expect(target.const_get(node_name, false)).to(equal(Kimera::SyntaxTypes.const_get(node_name)))
    end

    it "keeps a constant already there" do
      existing = Module.new.tap { |space| space.const_set(node_name, :sentinel) }
      Kimera::SyntaxTypes::Import.new(existing).call
      expect(existing.const_get(node_name, false)).to(eq(:sentinel))
    end
  end

  # A weave whose points stitch together two at a time at most.
  def pairwise = Class.new(Kimera::Overlay::FileWeave) { def attempt(points) = points.size <= 2 ? [:woven] : [] }

  it "backs out merged weave points until the combined render succeeds" do
    points = %i[a b c d]
    expect(pairwise.allocate.__send__(:merge, points, points.size)).to(eq(%i[a b]))
  end
end
