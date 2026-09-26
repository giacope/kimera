# frozen_string_literal: true

require "kimera/audit/operator_audit"
require "kimera/cli/baseline"
require "kimera/cli/mutant"
require "kimera/cli/run/pass"
require "kimera/execution/child_process"
require "kimera/execution/harness"
require "kimera/execution/parallel_test_databases"
require "kimera/execution/pool_driver"
require "kimera/execution/reload"
require "kimera/operators/node_swap"
require "kimera/rewrite/directive"
require "kimera/support/syntax_types"
require "kimera/synthesis/file_weave"
require "json"
require "stringio"
require "tmpdir"

RSpec.describe Kimera::Execution, :aggregate_failures do
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

  it "reports the parser detail for malformed baseline reports" do
    Dir.mktmpdir do |dir|
      report = File.join(dir, "broken.json")
      output = File.join(dir, "baseline.yml")
      File.write(report, "{")
      detail = malformation("{")
      errors = StringIO.new

      argv = ["create", report, "--reason", "legacy", "--output", output]
      status = Kimera::CLI::Baseline.new(errors: errors).run(argv)

      expect(status).to(eq(1))
      expect(errors.string).to(include("unreadable report #{report}", detail))
    end
  end

  it "rejects noninteger mutant IDs and explains malformed rerun reports" do
    errors = StringIO.new
    cli = Kimera::CLI::Mutant.new(errors: errors)
    expect(cli.run(["not-an-id", "--report", "unused.json"])).to(eq(1))
    expect(errors.string).to(include("mutant ID must be an integer"))

    Dir.mktmpdir do |dir|
      report = File.join(dir, "broken.json")
      File.write(report, "{")
      detail = malformation("{")
      errors.truncate(0)
      errors.rewind

      expect(cli.run(["1", "--report", report, "--rerun"])).to(eq(1))
      expect(errors.string).to(include("unreadable report #{report}", detail))
    end
  end

  it "matches string-keyed coverage entries" do
    pass = Kimera::CLI::Run::Pass.allocate
    expect(pass.__send__(:matches?, { "7" => ["spec/critical_spec.rb"] }, 7, "critical")).to(be(true))
  end

  it "redirects both child streams before rebinding Ruby globals" do
    child = Class.new { include Kimera::Execution::ChildProcess }.new
    out = Object.const_get(:STDOUT)
    error = Object.const_get(:STDERR)
    allow(out).to(receive(:reopen))
    allow(error).to(receive(:reopen))

    child.__send__(:silence!)

    expect(out).to(have_received(:reopen).with(File::NULL, "w"))
    expect(error).to(have_received(:reopen).with(File::NULL, "w"))
    expect($stdout).to(equal(out))
    expect($stderr).to(equal(error))
  end

  it "exposes the harness skip map and delegates its spawner to the rig" do
    token = Object.new
    harness = Kimera::Execution::Harness.new(registry: Object.new, adapter: Object.new)
    harness.instance_variable_set(:@_rig, instance_double(Kimera::Execution::Rig, spawner: token))

    expect(harness.skipped).to(eq({}))
    expect(harness.__send__(:spawner)).to(equal(token))
  end

  it "reports teardown failures with the injected error stream" do
    errors = StringIO.new
    databases = Kimera::Execution::ParallelTestDatabases.new(adapter: Object.new, jobs: 2, errors: errors)
    allow(databases).to(receive(:cleanup).and_raise(RuntimeError, "teardown boom"))

    databases.before_exit(1)

    expect(errors.string).to(eq("kimera: parallelize_teardown failed (RuntimeError: teardown boom)\n"))
    fallback = Kimera::Execution::ParallelTestDatabases.new(adapter: Object.new, jobs: 2)
    expect(fallback.__send__(:errors)).to(equal($stderr))
  end

  it "reports unavailable per-worker database support with exception detail" do
    stub_const("ActiveRecord", Module.new)
    stub_const("ActiveRecord::Base", Class.new)
    errors = StringIO.new
    databases = Kimera::Execution::ParallelTestDatabases.new(adapter: Object.new, jobs: 2, errors: errors)
    allow(databases).to(receive(:require).with("active_record/test_databases").and_raise(LoadError, "missing helper"))

    databases.__send__(:register!)

    notice = "kimera: per-worker test databases unavailable " \
      "(LoadError: missing helper); workers share one database\n"
    expect(errors.string).to(eq(notice))
  end

  def pool(database: instance_double(Kimera::Execution::ParallelTestDatabases))
    Kimera::Execution::Pool.new(
      adapter: Object.new, registry: Object.new, isolation: Object.new,
      coverage: {}, paralleldb: database, soft: 1.0, hard: 2.0, leak: 3, jobs: 1
    )
  end

  it "runs and finishes a pool duty through its shift and pipes" do
    shift = instance_spy(Kimera::Execution::Shift)
    request = Object.new
    response = instance_spy(IO)
    pipes = instance_double(Kimera::Execution::Pool::Channels, req_r: request, res_w: response)
    duty = Kimera::Execution::Pool::Duty.new(:coverage, 4, pipes)
    database = instance_double(Kimera::Execution::ParallelTestDatabases, before_exit: nil)
    duty.run(shift)
    duty.finish(database)

    expect(database).to(have_received(:before_exit).with(4))
    expect(shift).to(have_received(:coverage).with(request, response))
    expect(response).to(have_received(:close))
  end

  it "performs every pool child boot step and always finishes service" do
    database = instance_double(Kimera::Execution::ParallelTestDatabases, after_fork: nil, before_exit: nil)
    runner = pool(database: database)
    pipes = instance_spy(Kimera::Execution::Pool::Channels)
    duty = instance_spy(Kimera::Execution::Pool::Duty, pipes: pipes, index: 5)
    allow(runner).to(receive(:silence!))
    allow(runner).to(receive(:exit!))

    runner.__send__(:boot, duty)

    expect(pipes).to(have_received(:child!))
    expect(runner).to(have_received(:silence!))
    expect(database).to(have_received(:after_fork).with(5))
    expect(duty).to(have_received(:run).with(instance_of(Kimera::Execution::Shift)))
    expect(duty).to(have_received(:finish).with(database))
    expect(runner).to(have_received(:exit!).with(0))
    expect(runner.__send__(:build)).to(be_a(Kimera::Execution::Shift))
  end

  it "boots a pool duty inside the fork block" do
    runner = pool(database: instance_double(Kimera::Execution::ParallelTestDatabases))
    duty = Object.new
    allow(runner).to(receive(:fork).and_yield.and_return(123))
    allow(runner).to(receive(:boot))

    expect(runner.__send__(:spawn, duty)).to(eq(123))
    expect(runner).to(have_received(:boot).with(duty))
  end

  it "closes and writes both sides of a reload errand" do
    reader = instance_spy(IO)
    writer = instance_spy(IO)
    errand = Kimera::Execution::Reload::Errand.new(8, reader, writer)

    errand.child!
    errand.emit("payload")

    expect(reader).to(have_received(:close))
    expect(writer).to(have_received(:puts).with("payload"))
    expect(writer).to(have_received(:close))
  end

  it "performs every reload worker step" do
    reload = Kimera::Execution::Reload.new(registry: Object.new, adapter: Object.new, isolation: Object.new, root: ".")
    errand = instance_spy(Kimera::Execution::Reload::Errand, id: 9)
    allow(reload).to(receive(:silence!))
    allow(reload).to(receive(:report).with(9).and_return("result"))
    allow(reload).to(receive(:exit!))

    reload.__send__(:work, errand)

    expect(errand).to(have_received(:child!))
    expect(reload).to(have_received(:silence!))
    expect(errand).to(have_received(:emit).with("result"))
    expect(reload).to(have_received(:exit!).with(0))
  end

  it "runs reload work inside the fork block before closing the parent writer" do
    reload = Kimera::Execution::Reload.new(registry: Object.new, adapter: Object.new, isolation: Object.new, root: ".")
    errand = instance_spy(Kimera::Execution::Reload::Errand)
    allow(reload).to(receive(:fork).and_yield.and_return(456))
    allow(reload).to(receive(:work))

    expect(reload.__send__(:child, errand)).to(eq(456))
    expect(reload).to(have_received(:work).with(errand))
    expect(errand).to(have_received(:parent!))
  end

  it "defines a frozen, keyed node-swap operator subclass" do
    mutations = { Object => { label: "object", to: String } }
    operator = Kimera::Operators::NodeSwap.define(:object_swap, mutations)

    expect(operator.superclass).to(eq(Kimera::Operators::NodeSwap))
    expect(operator::MUTATIONS).to(eq(mutations))
    expect(operator::MUTATIONS).to(be_frozen)
    expect(operator.key).to(eq(:object_swap))
  end

  it "builds frozen directive lookup tables from alternating entries" do
    table = Kimera::Rewrite::Directive.table("one", :first, "two", :second)
    expect(table).to(eq("one" => :first, "two" => :second))
    expect(table).to(be_frozen)
  end

  it "installs syntax node constants once without replacing existing constants" do
    name = Kimera::SyntaxTypes.constants.grep(/Node\z/).first
    expect(name).not_to(be_nil)

    target = Module.new
    Kimera::SyntaxTypes::Installer.new(target).call
    expect(target.const_get(name, false)).to(equal(Kimera::SyntaxTypes.const_get(name)))

    sentinel = Object.new
    existing = Module.new
    existing.const_set(name, sentinel)
    Kimera::SyntaxTypes::Installer.new(existing).call
    expect(existing.const_get(name, false)).to(equal(sentinel))
  end

  it "backs out merged weave points until the combined render succeeds" do
    weave = Kimera::Overlay::FileWeave.allocate
    points = %i[a b c d]
    allow(weave).to(receive(:bisect) { |half| half })
    allow(weave).to(receive(:attempt) { |merged| merged.size <= 2 })

    expect(weave.__send__(:merge, points, points.size)).to(eq(%i[a b]))
  end
end
