# frozen_string_literal: true

require "kimera/execution/baseline_pass"
require "kimera/frameworks/adapter"
require "kimera/registry/builder"

# A serial baseline runs in kimera's own process: a test that sends it a signal
# nothing traps would end the run without a word.
RSpec.describe(Kimera::Execution::BaselinePass) do
  let(:registry) { Kimera::RegistryScan.new.source("def a(x, y)\n  x > y\nend\n", file: "calc.rb") }

  # Each test covers the mutant, as a guard it runs would record.
  def adapter(error)
    mutant = registry.each.first.first.id
    Class.new(Kimera::Frameworks::Adapter) do
      define_method(:test_ids) { %w[t1 t2] }
      define_method(:reproduce) { |failed| "rspec #{failed.join(" ")}" }
      define_method(:run) do |ids|
        Kimera::RUNTIME.active?(mutant)
        raise(error) if ids == ["t1"]
        Kimera::Frameworks::RunOutcome.new(passed: true, failed_ids: [])
      end
    end.new
  end

  it "fails the baseline on the test whose signal nothing trapped, and only that test" do
    pass = described_class.new(adapter: adapter(SignalException.new("TERM")), registry: registry)
    detail = /not green: t1\n  t1:\n    SignalException: SIGTERM\n    nothing trapped/
    expect { pass.measure! }.to(raise_error(Kimera::Execution::BaselineFailure, detail))
  end

  it "lets an interrupt stop the run" do
    pass = described_class.new(adapter: adapter(Interrupt.new), registry: registry)
    expect { pass.measure! }.to(raise_error(Interrupt))
  end
end
