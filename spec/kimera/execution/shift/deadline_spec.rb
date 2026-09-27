# frozen_string_literal: true

require "kimera/execution/shift"

# Frameworks rescue the soft timeout's interrupt as a test failure, so the
# attempt checks the clock itself after each failing run.
RSpec.describe(Kimera::Execution::Shift::Deadline) do
  def deadline(seconds, times)
    clock = times.dup
    described_class.new(seconds, clock: -> { clock.shift })
  end

  def check(seconds, times)
    budget = deadline(seconds, times)
    budget.guard { budget.check!("t1") }
  end

  it "expires the moment the soft timeout is spent" do
    expect { check(1.0, [10.0, 11.0]) }.to(raise_error(Timeout::Error, "soft timeout (1.0s) expired while t1 ran"))
  end

  it "doesn't expire a moment before" do
    expect { check(1.0, [10.0, 10.99]) }.not_to(raise_error)
  end

  it "never expires without a soft timeout" do
    expect { check(nil, [10.0, 1e9]) }.not_to(raise_error)
  end

  it "returns what the guarded block returns" do
    expect(deadline(1.0, [0.0]).guard { :done }).to(eq(:done))
  end

  it "measures from the start of each guard" do
    budget = deadline(1.0, [0.0, 5.0, 5.5])
    budget.guard { :first }
    expect { budget.guard { budget.check!("t1") } }.not_to(raise_error)
  end
end
