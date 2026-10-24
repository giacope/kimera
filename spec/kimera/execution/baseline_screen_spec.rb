# frozen_string_literal: true

require "kimera/execution/baseline_screen"
require "kimera/frameworks/suite"

RSpec.describe(Kimera::Execution::BaselineScreen) do
  # Reruns ids "plainly": the ids in `red` fail; `ran` records each argv.
  def suite(red: [], output: "", ran: [])
    lambda do |env, *argv, chdir:|
      ran << [env, argv, chdir]
      File.write(argv.last, red.join("\n")) if argv.first == "plain"
      [output, Struct.new(:success?).new(red.empty?)]
    end
  end

  def adapter(plain: true)
    Class.new(Kimera::Frameworks::Suite) do
      def test_ids = %w[t1 t2 t3]
      define_method(:plain) { |ids, out| plain ? ["plain", *ids, out] : [] }
      def failed_plainly(_output, out) = File.read(out).split("\n")
    end.new
  end

  def screen(jobs: 1, **options)
    described_class.new(
      adapter: options.delete(:with) || adapter, root: "/project", jobs: jobs,
      suite: suite(**options)
    )
  end

  def failures = { "t1" => "SystemStackError: stack level too deep\n  frame", "t2" => nil }

  it "says nothing, and reruns nothing, when no baseline test failed", :aggregate_failures do
    ran = []
    expect(screen(ran: ran).call({})).to(be_nil)
    expect(ran).to(be_empty)
  end

  it "reruns the failing tests in the project root, outside kimera", :aggregate_failures do
    ran = []
    screen(red: %w[t1 t2], ran: ran).call(failures)
    env, argv, chdir = ran.first
    expect([env, argv.first(3), chdir]).to(eq([{ "KIMERA" => "1" }, %w[plain t1 t2], "/project"]))
  end

  # K3-3: tests red only under kimera were dropped as "covering nothing".
  def harness_error(**)
    screen(**).call(failures)
  rescue Kimera::Execution::BaselineFailure => error
    error.message
  end

  it "stops the run, naming them, when they pass plainly", :aggregate_failures do
    message = harness_error
    expect(message).to(start_with("harness error: 2 test(s) fail under kimera but pass in a plain run"))
    expect(message).to(include("\n  t1: SystemStackError: stack level too deep\n  t2\n"))
    expect(message).to(include("\n  plain run: rspec t1 t2 --order defined\n"))
  end

  # R4-KL9: dry-types holds `Coercions::Params.method(:to_int)` from load.
  it "names a method the suite took at load before any other cause" do
    captured = instance_double(Kimera::Execution::CapturedMethods, cause: "kimera redefined Coerce.to_int")
    allow(Kimera::Execution::CapturedMethods).to(receive(:new).with("/project").and_return(captured))
    expect(harness_error(jobs: 2)).to(end_with("\n  likely cause: kimera redefined Coerce.to_int"))
  end

  it "blames the forked workers when there were several, else what kimera changes", :aggregate_failures do
    expect(harness_error(jobs: 2)).to(end_with(described_class::CAUSES.fetch(:parallel)))
    expect(harness_error(jobs: 1)).to(end_with(described_class::CAUSES.fetch(:serial)))
  end

  it "stops on those that pass plainly even when others fail plainly too", :aggregate_failures do
    message = harness_error(red: ["t2"])
    expect(message).to(start_with("harness error: 1 test(s)"))
    expect(message).to(include("\n  t1: SystemStackError"))
    expect(message).not_to(include("\n  t2"))
  end

  it "folds the passing tests past the limit into a count" do
    screen.call((1..7).to_h { |n| ["t#{n}", "boom"] })
  rescue Kimera::Execution::BaselineFailure => error
    expect(error.message).to(include("\n  t5: boom\n  … and 2 more\n"))
  end

  # R5-KW4: the red tests that reached a mutant are screened the same way.
  it "stops on the red tests that pass plainly, and lets the run go on when they fail plainly too",
    :aggregate_failures do
    expect { screen.plainly!(failures) }.to(raise_error(Kimera::Execution::BaselineFailure, /\Aharness error: 2 test/))
    expect(screen(red: %w[t1 t2]).plainly!(failures)).to(be_nil)
  end

  it "excludes them, coverage unknown, when they fail plainly too", :aggregate_failures do
    notice = screen(red: %w[t1 t2]).call(failures)
    expect(notice).to(include("2 test(s) fail in the baseline, in a plain run too"))
    expect(notice).to(include("their coverage is unknown"))
  end

  it "counts every test as failing plainly when the red run names none of them" do
    notice = screen(red: ["elsewhere"]).call(failures)
    expect(notice).to(start_with("kimera: 2 test(s) fail in the baseline"))
  end

  it "excludes them when the framework has no plain rerun" do
    expect(screen(with: adapter(plain: false)).call(failures)).to(include("2 test(s) fail in the baseline"))
  end

  it "excludes them when the plain command cannot start" do
    broken = described_class.new(adapter: adapter, root: "/project", jobs: 1, suite: ->(*, **) { raise(Errno::ENOENT) })
    expect(broken.call(failures)).to(include("2 test(s) fail in the baseline"))
  end
end
