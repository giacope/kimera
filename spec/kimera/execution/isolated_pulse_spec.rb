# frozen_string_literal: true

require "kimera/execution/isolated_pulse"
require "tmpdir"

RSpec.describe(Kimera::Execution::IsolatedPulse) do
  let(:time) { [100.0] }
  let(:clock) { -> { time.first } }

  def watch(path) = described_class.new(path, 5.0, clock: clock)

  def at(seconds) = time[0] = 100.0 + seconds

  def beat(path) = File.write(path, ".", mode: "a")

  it "expires once the limit passes without a beat", :aggregate_failures do
    Dir.mktmpdir do |dir|
      pulse = watch(File.join(dir, "pulse")).observed
      at(4.9)
      expect(pulse.observed.expired?).to(be(false))
      at(5.0)
      expect(pulse.observed.expired?).to(be(true))
    end
  end

  it "renews the deadline from each new beat", :aggregate_failures do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "pulse")
      pulse = watch(path).observed
      at(4.0)
      beat(path)
      renewed = pulse.observed
      expect(renewed.expired?).to(be(false))
      at(8.9)
      expect(renewed.observed.expired?).to(be(false))
      at(9.0)
      expect(renewed.observed.expired?).to(be(true))
    end
  end

  it "does not renew on a pulse that has not grown since the last look", :aggregate_failures do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "pulse")
      beat(path)
      at(1.0)
      pulse = watch(path).observed
      at(6.0)
      expect(pulse.observed.expired?).to(be(true))
    end
  end
end
