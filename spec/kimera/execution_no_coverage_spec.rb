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

using ResultFields

RSpec.describe Kimera::Execution, :aggregate_failures do
  let(:errors) { StringIO.new }

  def malformation(input)
    JSON.parse(input)
  rescue JSON::ParserError => error
    error.message
  end

  it "falls back to the original source when audit reprinting fails" do
    rendering = Kimera::Operators::Audit::Rendering
    expect(rendering.new("def (", "def (").verdict).to(eq(Kimera::Operators::Audit::IDENTICAL))
    expect(rendering.new("def (", "rendered").verdict).to(eq(Kimera::Operators::Audit::OK))
  end

  describe "a malformed report" do
    let(:dir) { Dir.mktmpdir }

    after { FileUtils.remove_entry(dir) }

    def broken = File.join(dir, "broken.json").tap { |path| File.write(path, "{") }

    def kimera(*argv) = ended(Kimera::CLI.new(io: StringIO.new, errors: errors).run(argv), StringIO.new, errors)

    def mutant(*argv) = kimera("mutant", *argv)

    it "is explained with the parser's detail when creating a baseline" do
      argv = ["create", broken, "--reason", "legacy", "--output", File.join(dir, "baseline.yml")]
      status = Dir.chdir(dir) { kimera("baseline", *argv) }
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
    files = { 7 => [nil, "app/models/order.rb"] }
    route = Kimera::CLI::Run::Route.new(files, { isolate_when_covered_by: ["critical"] })
    expect(route.split([7]) { { "7" => ["spec/critical_spec.rb"] } }).to(eq([[7], []]))
  end

  def reload(trial) = Kimera::Execution::Reload.new(registry: Kimera::Registry.new, adapter: Object.new, trial: trial)

  def told(&report) = Class.new { define_method(:report) { |_id, errand| report[errand] } }.new

  def errored(errand, detail = "x") = errand.report(status: "error", fails: [], detail: detail, ms: 0)

  def noisy
    told do |errand|
      $stdout.print("ruby out")
      $stderr.print("ruby err")
      system("echo shell out; echo shell err >&2")
      errored(errand)
    end
  end

  def silenced_output
    IO.popen("-") do |pipe|
      next pipe.read if pipe
      IO.for_fd(2, autoclose: false).reopen(IO.for_fd(1, autoclose: false))
      $stdout.print("before|")
      $stdout.flush
      reload(noisy).run(9, deadline: 10.0, tests: [])
      exit!(0)
    end
  end

  it "points the child's descriptors 1 and 2, and Ruby's streams, at the null device" do
    expect(silenced_output).to(eq("before|"))
  end

  describe "worker databases" do
    let(:databases) { Kimera::Execution::WorkerDatabases.new(jobs: 2, errors: errors) }

    def unavailable
      "kimera: per-worker test databases unavailable (LoadError: missing helper); workers share one database\n"
    end

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
      FakeRails.unconnected(self)
      parallelization('LoadError, "missing helper"')
      databases.before_fork(FakeConnections.new)
      expect(errors.string).to(start_with(unavailable))
    end
  end

  def pool(database: FakeDatabases.new)
    Kimera::Execution::Pool.new(
      adapter: Object.new, registry: Object.new, isolation: Object.new,
      coverage: {}, paralleldb: database, soft: 1.0, hard: 2.0, jobs: 1
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

  def ledger(notes, &setup)
    Class.new do
      define_method(:after_fork) do |index|
        notes.puts(JSON.generate(["fork", index]))
        setup&.call
      end
      define_method(:before_exit) { |index| notes.puts(JSON.generate(["exit", index])) }
    end.new
  end

  def recording(notes)
    Class.new(Kimera::Execution::Pool::Armed) do
      define_method(:shift) do |**options|
        Class.new do
          define_method(:serve) do |requests, _responses|
            $stdout.print("loud")
            requests.read
            options.fetch(:pulse).call
            notes.puts(JSON.generate(["run", Process.getpgrp == Process.pid, options.fetch(:hard).to_s]))
          end
        end.new
      end
    end.new
  end

  def spawned(database, armed)
    pool = Kimera::Execution::Pool.new(
      adapter: Object.new, registry: Object.new, isolation: Object.new,
      coverage: {}, paralleldb: database, soft: 1.0, hard: 2.0, leak: 3, jobs: 1, armed: armed
    )
    pid, request, response = pool.spawner(:serve).call(5)
    request.close
    [heard(response, pid), Process.wait2(pid).last]
  end

  def heard(response, pid)
    Timeout.timeout(10) { response.readlines(chomp: true) }.map { |line| JSON.parse(line) }
  rescue Timeout::Error
    Process.kill("KILL", pid)
    raise
  end

  def noted(notes, armed: recording(notes.last), &setup)
    reader, writer = notes
    said, status = spawned(ledger(writer, &setup), armed)
    writer.close
    [reader.readlines(chomp: true).map { |line| JSON.parse(line) }, said, status]
  end

  describe "a pool child" do
    let(:notes) { IO.pipe }

    it "takes the child's pipe ends and silences it" do
      expect(descriptor_one { noted(notes) { $stdout.print("loud") } }).to(eq(""))
    end

    it "gives the worker its database, runs the duty through a shift and always retires it" do
      seen, = noted(notes)
      expect(seen).to(eq([["fork", 5], ["run", true, "2.0"], ["exit", 5]]))
    end

    it "boots inside the fork block, as the leader of a process group, and exits cleanly" do
      seen, _, status = noted(notes)
      expect([seen[1].take(2), status.exitstatus]).to(eq([["run", true], 0]))
    end

    it "builds a shift for the duty" do
      _, said, = noted(notes, armed: Kimera::Execution::Pool::Armed.new)
      expect(said).to(eq([{ "t" => "done" }]))
    end

    it "hands the shift a pulse that ticks through the worker's duty" do
      _, said, = noted(notes)
      expect(said).to(eq([{ "t" => "tick" }]))
    end

    it "keeps a test's raised soft limit under the hard watchdog" do
      seen, = noted(notes)
      patience = Kimera::Execution::Patience.new(0.1, timings: { "t" => 5.0 }, hard: Float(seen[1].last))
      expect(patience.limit("t")).to(eq(1.0))
    end

    it "retires a worker whose after-fork setup raised with what it raised", :aggregate_failures do
      seen, said, = noted(notes) { raise(RuntimeError, "search index unavailable") }
      expect(said.map { |line| line.fetch("detail").lines.first.chomp }).to(
        eq(["worker 5's after-fork setup raised RuntimeError: search index unavailable"])
      )
      expect(seen).to(eq([["fork", 5], ["exit", 5]]))
    end
  end

  def unprepared(error)
    pipes = Kimera::Execution::Pool::Channels.new(*IO.pipe, *IO.pipe)
    Kimera::Execution::Pool::Duty.new(:serve, 5, pipes).prepare(FakeDatabases.new { raise(error) })
  rescue Kimera::Execution::Pool::Unprepared => error
    error
  end

  it "keeps the setup error's backtrace" do
    expect(unprepared(ScriptError.new("x")).backtrace.first).to(include(__FILE__))
  end

  describe "a reload errand" do
    def emitted
      reader, writer = IO.pipe
      Kimera::Execution::Reload::Errand.new(8, [], reader, writer).emit("payload")
      [writer.closed?, reader.read]
    end

    it "writes its payload and closes its own end" do
      expect(emitted).to(eq([true, "payload\n"]))
    end

    it "flushes each tick straight to the parent" do
      IO.pipe do |parent, child|
        Kimera::Execution::Reload::Errand.new(8, [], IO.pipe.first, child).tick("t1")
        expect(parent.read_nonblock(16)).to(eq("tick\n"))
      end
    end
  end

  describe "a reload worker" do
    def worked(trial) = reload(trial).run(9, deadline: 10.0, tests: [])

    it "leads its process group before it takes the child's pipe ends" do
      leader = told { |errand| errored(errand, Process.getpgrp == Process.pid ? "leader" : "member") }
      expect(worked(leader).detail).to(eq("leader"))
    end

    it "silences the child and emits the report on its errand" do
      result = nil
      expect(descriptor_one { result = worked(noisy) }).to(eq(""))
      expect([result.mutant_id, result.status]).to(eq([9, :error]))
    end

    def hooked
      reader, writer = IO.pipe
      worked(told { |errand| errored(errand).tap { at_exit { writer.print("ran its exit hooks") } } })
      writer.close
      reader.read
    end

    it "exits at once, without running the exit hooks it inherited" do
      expect(hooked).to(eq(""))
    end

    def stuck(notes, gate)
      told do |_errand|
        gate.last.close
        notes.last.puts(Process.pid)
        Process.kill("INT", Process.ppid)
        gate.first.read
      end
    end

    def interrupted(notes, gate)
      fork do
        Signal.trap("INT", "DEFAULT")
        worked(stuck(notes, gate))
        exit!(0)
      rescue Interrupt
        exit!(2)
      end
    end

    def gone?(pid)
      Process.kill(0, pid)
      false
    rescue Errno::ESRCH
      true
    end

    def abandoned
      notes, gate = Array.new(2) { IO.pipe }
      parent = interrupted(notes, gate)
      child = Integer(Timeout.timeout(10) { notes.first.gets })
      [Process.wait2(parent).last.exitstatus, gone?(child)]
    ensure
      gate.last.close
    end

    it "takes a reload child down with it when kimera is interrupted" do
      expect(abandoned).to(eq([2, true]))
    end
  end

  it "swaps a node by its class into the mutation the subclass names" do
    operator = Kimera::Operators::BooleanLiteral.new
    node = Kimera::Syntax.parse("true").value.statements.body.first

    expect(operator.key).to(eq("boolean_literal"))
    expect(operator.variants(node).map { it.to_h.fetch(:label) }).to(eq(["true => false"]))
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

  def pairwise(woven)
    Class.new(Kimera::Overlay::FileWeave) do
      define_method(:attempt) { |points| points.size <= 2 ? [woven] : [] }
    end
  end

  def woven(skipped)
    Class.new do
      define_method(:skip!) { |points| skipped.concat(points.map(&:line)) }
      def settle!(*) = self
    end.new
  end

  def weavable(line)
    Struct.new(:line) do
      def to_h = { "location" => { "start_line" => line } }
      def mark!(_reason) = self
    end.new(line)
  end

  it "backs out merged weave points until the combined render succeeds" do
    skipped = []
    pairwise(woven(skipped)).new("f.rb", {}, [1, 2, 3, 4].map { weavable(it) }, []).result(StringIO.new)
    expect(skipped).to(eq([3, 4]))
  end
end
