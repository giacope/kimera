# frozen_string_literal: true

require "kimera/execution/shift"

# Frameworks rescue the soft timeout's interrupt as a test failure, so the
# guard checks the clock itself after each run. Every covering test run gets
# the whole budget: a mutant many tests cover is not a timeout for that alone.
RSpec.describe(Kimera::Execution::Shift::Deadline) do
  def deadline(seconds, times, beat: described_class::SILENT)
    clock = times.dup
    described_class.new(seconds, clock: -> { clock.shift }, beat: beat)
  end

  it "expires a test run the moment the soft timeout is spent" do
    expect { deadline(1.0, [10.0, 11.0]).guard("t1") { :ran } }
      .to(raise_error(Timeout::Error, "soft timeout (1.0s) expired while t1 ran"))
  end

  it "returns what the run returns a moment before" do
    expect(deadline(1.0, [10.0, 10.99]).guard("t1") { :ran }).to(eq(:ran))
  end

  it "never expires without a soft timeout" do
    expect(deadline(nil, [10.0, 1e9]).guard("t1") { :ran }).to(eq(:ran))
  end

  it "gives every test run its own budget" do
    budget = deadline(1.0, [0.0, 0.9, 5.0, 5.9])
    expect([budget.guard("t1") { 1 }, budget.guard("t2") { 2 }]).to(eq([1, 2]))
  end

  it "interrupts a run that outlasts the budget" do
    expect { described_class.new(0.05).guard("t1") { sleep(5) } }.to(raise_error(Timeout::Error))
  end

  # The parent's hard watchdog renews on each beat, so it too times one test.
  it "beats before each test run" do
    beats = []
    budget = deadline(nil, [0.0] * 4, beat: -> { beats << :beat })
    2.times { budget.guard("t1") { beats << :run } }
    expect(beats).to(eq(%i[beat run beat run]))
  end
end
