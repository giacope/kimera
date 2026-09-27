# frozen_string_literal: true

require "kimera/execution/harness"
require "kimera/registry/builder"
require "stringio"

# The warm baseline's notice for tests that stalled under parallel load.
RSpec.describe(Kimera::Execution::Harness) do
  let(:registry) do
    Kimera::RegistryScan.new.source(<<~RUBY, file: "calc.rb")
      def a(x, y)
        x > y
      end
    RUBY
  end

  it "prints the stall notice with the run's hard timeout and width", :aggregate_failures do
    errors = StringIO.new
    harness = described_class.new(registry: registry, adapter: nil, errio: errors, hard_timeout: 7.0, jobs: 3)
    harness.__send__(:state).recovered = { "A#t" => "trace" }
    harness.__send__(:notice)

    expect(errors.string).to(start_with("kimera: 1 baseline test(s) hit the hard timeout (7.0s) with 3 workers"))
    expect(errors.string).to(end_with("  A#t:\n    trace\n"))
  end

  it "prints nothing when no baseline test stalled" do
    errors = StringIO.new
    described_class.new(registry: registry, adapter: nil, errio: errors).__send__(:notice)
    expect(errors.string).to(be_empty)
  end
end
