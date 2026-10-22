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
require "kimera/support/syntax_types"
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
    allow(Unparser).to(receive(:parse).and_raise(StandardError, "unparseable"))
    rendering = Kimera::Operators::Audit::Rendering.new("original", "rendered")

    expect(rendering.__send__(:reprinted)).to(eq("original"))
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

  it "exposes the harness skip map and delegates its spawner to the rig" do
    token = Object.new
    harness = Kimera::Execution::Harness.build(registry: Object.new, adapter: Object.new)
    harness.instance_variable_set(:@_rig, instance_double(Kimera::Execution::Rig, spawner: token))

    expect(harness.skipped).to(eq({}))
    expect(harness.__send__(:spawner)).to(equal(token))
  end

  describe "worker databases" do
    let(:databases) { Kimera::Execution::WorkerDatabases.new(jobs: 2, errors: errors) }

    def unavailable
      "kimera: per-worker test databases unavailable (LoadError: missing helper); workers share one database\n"
    end

    def unloadable
      allow(databases).to(receive(:eligible?).and_return(true))
      allow(databases).to(receive(:require).with("active_record/test_databases").and_raise(LoadError, "missing helper"))
    end

    it "report teardown failures with the injected error stream" do
      allow(databases).to(receive(:cleanup).and_raise(RuntimeError, "teardown boom"))
      databases.before_exit(1)
      expect(errors.string).to(eq("kimera: parallelize_teardown failed (RuntimeError: teardown boom)\n"))
    end

    it "report to standard error by default" do
      expect(Kimera::Execution::WorkerDatabases.new(jobs: 2).__send__(:errors)).to(equal($stderr))
    end

    it "report unavailable per-worker database support with exception detail" do
      stub_const("ActiveRecord::Base", Class.new)
      unloadable
      databases.__send__(:register!)
      expect(errors.string).to(eq(unavailable))
    end
  end

  def pool(database: instance_double(Kimera::Execution::WorkerDatabases))
    Kimera::Execution::Pool.new(
      adapter: Object.new, registry: Object.new, isolation: Object.new,
      coverage: {}, paralleldb: database, soft: 1.0, hard: 2.0, leak: 3, jobs: 1
    )
  end

  describe "a pool duty" do
    let(:shift) { instance_spy(Kimera::Execution::Shift) }
    let(:response) { instance_spy(IO) }
    let(:database) { instance_double(Kimera::Execution::WorkerDatabases, before_exit: nil) }

    def served
      pipes = instance_double(Kimera::Execution::Pool::Channels, req_r: :request, res_w: response)
      Kimera::Execution::Pool::Duty.new(:coverage, 4, pipes).tap do |duty|
        duty.run(shift)
        duty.finish(database, nil)
      end
    end

    it "serves its errand through the shift" do
      served
      expect(shift).to(have_received(:coverage).with(:request, response))
    end

    it "tells the databases its worker exits" do
      served
      expect(database).to(have_received(:before_exit).with(4))
    end

    it "closes its response pipe without writing to it" do
      served
      expect(response).to(have_received(:close))
      expect(response).not_to(have_received(:puts))
    end
  end

  describe "a pool child's boot" do
    let(:database) { instance_double(Kimera::Execution::WorkerDatabases, after_fork: nil, before_exit: nil) }
    let(:runner) do
      pool(database: database).tap { |child| allow(child).to(receive_messages(silence!: nil, exit!: nil)) }
    end
    let(:pipes) { instance_spy(Kimera::Execution::Pool::Channels) }
    let(:duty) { instance_spy(Kimera::Execution::Pool::Duty, pipes: pipes, index: 5) }

    def booted = runner.__send__(:boot, duty)

    it "takes the child's pipe ends and silences it" do
      booted
      expect(pipes).to(have_received(:child!))
      expect(runner).to(have_received(:silence!))
    end

    it "gives the worker its database" do
      booted
      expect(database).to(have_received(:after_fork).with(5))
    end

    it "runs the duty through a shift and always retires it" do
      booted
      expect(duty).to(have_received(:run).with(instance_of(Kimera::Execution::Shift)))
      expect(duty).to(have_received(:retire).with(database, nil))
    end

    it "exits cleanly" do
      booted
      expect(runner).to(have_received(:exit!).with(0))
    end

    it "builds a shift for the duty" do
      expect(runner.__send__(:build, duty)).to(be_a(Kimera::Execution::Shift))
    end
  end

  # The hard watchdog renews on each test's beat, so a slow test's raised soft
  # limit stays a second under it and the soft timeout still fires first.
  it "keeps a test's raised soft limit under the hard watchdog" do
    expect(pool.__send__(:soft_ceiling)).to(eq(1.0))
  end

  it "hands the shift a pulse that ticks through the worker's duty" do
    duty = instance_spy(Kimera::Execution::Pool::Duty)
    pool.__send__(:pulse, duty).call
    expect(duty).to(have_received(:pulse))
  end

  def forking(child, pid) = child.tap { allow(child).to(receive(:fork).and_yield.and_return(pid)) }

  # Leading its own process group, the worker takes what its tests start
  # down with it when it is killed.
  it "boots a pool duty inside the fork block, as the leader of a process group" do
    runner = forking(pool, 123)
    allow(runner).to(receive(:lead))
    allow(runner).to(receive(:boot)) { expect(runner).to(have_received(:lead)) }
    expect(runner.__send__(:spawn, :duty)).to(eq(123))
    expect(runner).to(have_received(:boot).with(:duty))
  end

  describe "a reload errand" do
    let(:reader) { instance_spy(IO) }
    let(:writer) { instance_spy(IO) }

    def emitted
      Kimera::Execution::Reload::Errand.new(8, [], reader, writer).tap do |errand|
        errand.child!
        errand.emit("payload")
      end
    end

    it "closes the parent's end in the child" do
      emitted
      expect(reader).to(have_received(:close))
    end

    it "writes its payload and closes its own end" do
      emitted
      expect(writer).to(have_received(:puts).with("payload"))
      expect(writer).to(have_received(:close))
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
    let(:errand) { instance_spy(Kimera::Execution::Reload::Errand, id: 9) }

    def worked
      allow(reload).to(receive_messages(lead: nil, silence!: nil, exit!: nil, report: "result"))
      reload.__send__(:work, errand)
    end

    it "leads its process group before it takes the child's pipe ends" do
      allow(errand).to(receive(:child!)) { expect(reload).to(have_received(:lead)) }
      worked
      expect(errand).to(have_received(:child!))
    end

    it "silences the child and emits the report on its errand" do
      worked
      expect(reload).to(have_received(:silence!))
      expect(reload).to(have_received(:report).with(errand))
      expect(errand).to(have_received(:emit).with("result"))
    end

    it "exits cleanly" do
      worked
      expect(reload).to(have_received(:exit!).with(0))
    end

    # The child leads its own process group, so the terminal's Ctrl-C never
    # reaches it: an interrupted kimera kills and reaps it on the way out.
    it "takes a reload child down with it when kimera is interrupted" do
      pid = fork { sleep(300) }
      allow(errand).to(receive(:await).and_raise(Interrupt))
      expect { Timeout.timeout(10) { reload.__send__(:hear, errand, pid, 1.0) } }.to(raise_error(Interrupt))
      expect { Process.kill(0, pid) }.to(raise_error(Errno::ESRCH))
    end

    it "runs inside the fork block before closing the parent writer" do
      forking(reload, 456)
      allow(reload).to(receive(:work))
      expect(reload.__send__(:child, errand)).to(eq(456))
      expect(reload).to(have_received(:work).with(errand))
      expect(errand).to(have_received(:parent!))
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
      target = Module.new.tap { |space| Kimera::SyntaxTypes::Installer.new(space).call }
      expect(target.const_get(node_name, false)).to(equal(Kimera::SyntaxTypes.const_get(node_name)))
    end

    it "keeps a constant already there" do
      existing = Module.new.tap { |space| space.const_set(node_name, :sentinel) }
      Kimera::SyntaxTypes::Installer.new(existing).call
      expect(existing.const_get(node_name, false)).to(eq(:sentinel))
    end
  end

  it "backs out merged weave points until the combined render succeeds" do
    weave = Kimera::Overlay::FileWeave.allocate
    points = %i[a b c d]
    allow(weave).to(receive(:bisect) { |half| half })
    allow(weave).to(receive(:attempt) { |merged| merged.size <= 2 })

    expect(weave.__send__(:merge, points, points.size)).to(eq(%i[a b]))
  end
end
