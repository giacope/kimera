# frozen_string_literal: true

require "kimera/execution/shift"
require "kimera/frameworks/suite"
require "kimera/registry/builder"

# A covering test that runs past the soft timeout with the mutant on counts
# as detected only when, alone and with the mutant off, it passes in well
# under that timeout. A test that is slow without the mutant too cannot tell
# a hang from its own pace, so its expiry is no kill.
RSpec.describe(Kimera::Execution::Shift) do
  let(:registry) do
    Kimera::RegistryScan.new.source(<<~RUBY, file: "calc.rb")
      def a(x, y)
        x > y
      end
    RUBY
  end

  let(:target) { registry.each.first.first.id }
  let(:clock) { [0.0] }

  before { stub_const("Kimera::Execution::Shift::Deadline::CLOCK", -> { clock.first }) }

  after { Kimera::RUNTIME.reset! }

  # +script+ maps a test to its successive runs, as [seconds, passed?] pairs.
  def timed(script)
    now = clock
    Class.new do
      attr_reader :log

      define_method(:initialize) do
        @script = script.transform_values(&:dup)
        @log = []
      end

      define_method(:run) do |ids|
        id = ids.first
        @log << [id, Kimera::RUNTIME.active]
        took, passed = @script.fetch(id, []).shift || [0.0, true]
        now[0] += took
        Kimera::Frameworks::RunOutcome.new(passed: passed, failed_ids: passed ? [] : [id])
      end
    end.new
  end

  def worker(adapter, tests, **)
    described_class.new(
      adapter: adapter, registry: registry, coverage: { target => tests }, soft_timeout: 5.0, zygote: InlineZygote.new,
      **
    )
  end

  def hung = [6.0, true]

  it "is a timeout when the test passes quickly alone with the mutant off", :aggregate_failures do
    adapter = timed({ "t1" => [hung, [0.4, true]] })
    result = worker(adapter, %w[t1 t2]).evaluate(target)
    expect(result.status).to(eq(:timeout))
    expect(result.detail).to(
      eq("soft timeout (5.0s) expired while t1 ran with the mutant on; alone with it off, the test passed in 0.4s")
    )
    expect(adapter.log).to(eq([["t1", target], ["t1", nil]]))
  end

  # A slow example on a busy machine is not a hang: its limit is raised from
  # its own baseline (× 3 + 1s), never past the hard watchdog's ceiling.
  it "raises a slow test's soft limit from its baseline", :aggregate_failures do
    expect(worker(timed({ "t1" => [hung] }), %w[t1], timings: { "t1" => 2.0 }).evaluate(target).status)
      .to(eq(:survived))
    late = worker(timed({ "t1" => [[8.0, true], [0.4, true]] }), %w[t1], timings: { "t1" => 2.0 }, ceiling: 6.5)
    expect(late.evaluate(target).detail).to(start_with("soft timeout (6.5s) expired while t1 ran with the mutant on"))
  end

  it "takes no kill from a test that needs half the soft timeout or more without the mutant", :aggregate_failures do
    adapter = timed({ "t1" => [hung, [2.5, true]] })
    result = worker(adapter, %w[t1 t2]).evaluate(target)
    expect(result.status).to(eq(:harness_error))
    expect(result.detail).to(
      start_with("t1 ran past its soft timeout (5.0s) with the mutant on, and took 2.5s with it off")
    )
    expect(result.detail).to(end_with("killed it: raise --soft-timeout well above the test's own time"))
    expect(adapter.log).to(eq([["t1", target], ["t1", nil], ["t2", target]]))
  end

  it "counts a test just under half the soft timeout as clear" do
    expect(worker(timed({ "t1" => [hung, [2.49, true]] }), %w[t1]).evaluate(target).status).to(eq(:timeout))
  end

  it "lets the next covering test kill the mutant when a slow test cannot" do
    adapter = timed({ "t1" => [hung, [3.0, true]], "t2" => [[0.1, false], [0.1, false]] })
    expect(worker(adapter, %w[t1 t2]).evaluate(target).status).to(eq(:killed))
  end

  it "takes no kill when the test runs past the soft timeout with the mutant off too" do
    result = worker(timed({ "t1" => [hung, hung] }), %w[t1]).evaluate(target)
    expect(result.detail).to(start_with("t1 ran past its soft timeout (5.0s) with the mutant on and with it off, so"))
  end

  it "takes no kill when the test fails with the mutant off", :aggregate_failures do
    result = worker(timed({ "t1" => [hung, [0.1, false]] }), %w[t1]).evaluate(target)
    expect(result.detail).to(
      start_with("t1 ran past its soft timeout (5.0s) with the mutant on, and failed with it off, so")
    )
    expect(result.detail).to(end_with(": fix the test, or raise --soft-timeout well above the test's own time"))
  end
end
