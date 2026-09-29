# frozen_string_literal: true

require "kimera/execution/shift"
require "kimera/frameworks/adapter"

RSpec.describe(Kimera::Execution::Shift::Trial) do
  after { Kimera::Runtime.reset! }

  # Fails every run, logging whether the mutant was on.
  def failing(log)
    Class.new do
      define_method(:run) do |ids|
        log << Kimera::Runtime.active
        Kimera::Frameworks::RunOutcome.new(passed: false, failed_ids: ids)
      end
    end.new
  end

  it "stops at a failure past the deadline, before any confirmation run", :aggregate_failures do
    log = []
    expired = Object.new
    expired.define_singleton_method(:guard) do |test, &run|
      run.call
      raise(Timeout::Error, "late in #{test}")
    end
    expect { described_class.new(failing(log), 7, "t1", expired).verdict }.to(raise_error(Timeout::Error, "late in t1"))
    expect(log).to(eq([7]))
  end
end
