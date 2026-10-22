# frozen_string_literal: true

require "kimera/execution/isolated_pulse"
require "tmpdir"

RSpec.describe(Kimera::Execution::IsolatedPulse) do
  let(:time) { [100.0] }
  let(:clock) { -> { time.first } }

  def watch(path) = described_class.new(path, 5.0, clock: clock)

  def at(seconds) = time[0] = 100.0 + seconds

  def beat(path) = File.write(path, ".", mode: "a")

  it "expires once the limit passes without a beat" do
    Dir.mktmpdir do |dir|
      pulse = watch(File.join(dir, "pulse")).observed
      expect([4.9, 5.0].map { |seconds| at(seconds).then { pulse.observed.expired? } }).to(eq([false, true]))
    end
  end

  # Whether a pulse beaten at 4.0 has expired: when looked at again then, and
  # at each later time.
  def renewed(dir, times)
    path = File.join(dir, "pulse")
    pulse = watch(path).observed
    at(4.0)
    beat(path)
    looked = pulse.observed
    [looked.expired?, *times.map { |seconds| at(seconds).then { looked.observed.expired? } }]
  end

  it "renews the deadline from each new beat" do
    Dir.mktmpdir { |dir| expect(renewed(dir, [8.9, 9.0])).to(eq([false, false, true])) }
  end

  it "does not renew on a pulse that has not grown since the last look" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "pulse").tap { |file| beat(file) }
      pulse = at(1.0).then { watch(path).observed }
      expect(at(6.0).then { pulse.observed.expired? }).to(be(true))
    end
  end
end
