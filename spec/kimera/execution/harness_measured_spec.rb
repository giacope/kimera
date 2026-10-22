# frozen_string_literal: true

require "kimera/execution/harness"
require "kimera/frameworks/suite"
require "kimera/registry/builder"
require "tmpdir"

RSpec.describe(Kimera::Execution::Harness) do
  let(:dir) { Dir.mktmpdir("kimera-measured") }

  after { FileUtils.remove_entry(dir) }

  # Every test reaches the one mutant.
  def adapter(id)
    Class.new(Kimera::Frameworks::Suite) do
      define_method(:source) { |_files| self }
      define_method(:test_ids) { %w[t1 t2] }
      define_method(:run) do |ids|
        Kimera::RUNTIME.active?(id)
        Kimera::Frameworks::RunOutcome.new(passed: true, failed_ids: [], failures: {}) if ids
      end
    end.new
  end

  def registry
    path = File.join(dir, "measuredcalc.rb")
    File.write(path, "class Measuredcalc\n  def a(x) = x > 1\nend\n")
    Kimera::RegistryScan.new(root: dir).build([path])
  end

  def harness(catalog = registry)
    measured = ->(ids) { ids.last(1) }
    described_class.build(registry: catalog, adapter: adapter(catalog.each.first.first.id), measured: measured)
  end

  it "builds coverage from the tests its measured option picks" do
    stub_const("Measuredcalc", Class.new)
    expect(harness.tap { |warmed| warmed.warm!(["t1"]) }.coverage.values.uniq).to(eq([%w[t2]]))
  end
end
