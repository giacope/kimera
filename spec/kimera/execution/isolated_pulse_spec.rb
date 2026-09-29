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
      pulse = watch(File.join(dir, "pulse"))
      pulse.expired?
      at(4.9)
      expect(pulse.expired?).to(be(false))
      at(5.0)
      expect(pulse.expired?).to(be(true))
    end
  end

  it "renews the deadline from each new beat", :aggregate_failures do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "pulse")
      pulse = watch(path)
      pulse.expired?
      at(4.0)
      beat(path)
      expect(pulse.expired?).to(be(false))
      at(8.9)
      expect(pulse.expired?).to(be(false))
      at(9.0)
      expect(pulse.expired?).to(be(true))
    end
  end

  it "does not renew on a pulse that has not grown since the last look", :aggregate_failures do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "pulse")
      beat(path)
      pulse = watch(path)
      at(1.0)
      pulse.expired?
      at(6.0)
      expect(pulse.expired?).to(be(true))
    end
  end
end
