# frozen_string_literal: true

require "kimera/execution/boot"

# A suite whose test files load but select no test (an inclusion filter that
# matches nothing) would score every mutant as uncovered; the boot refuses it.
RSpec.describe(Kimera::Execution::Boot) do
  def adapter(ids)
    Class.new do
      define_method(:source) { |_files| self }
      define_method(:test_ids) { ids }
      define_method(:start) { :started }
    end.new
  end

  it "fails the baseline when the test files hold no test to run" do
    expect { described_class.new(adapter: adapter([]), isolate: false).suite(["spec/a_spec.rb"]) }
      .to(raise_error(Kimera::Execution::BaselineFailure, /\Abaseline has no tests to run: 1 test file\(s\) loaded/))
  end

  it "boots a suite with tests, and one with no test files at all", :aggregate_failures do
    expect { described_class.new(adapter: adapter(["t1"]), isolate: false).suite(["spec/a_spec.rb"]) }
      .not_to(raise_error)
    expect { described_class.new(adapter: adapter([]), isolate: false).suite([]) }.not_to(raise_error)
  end
end
