# frozen_string_literal: true

require "kimera/execution/isolated"
require "tmpdir"

RSpec.describe(Kimera::Execution::IsolatedExecution, :aggregate_failures) do
  let(:connections) { FakeConnections.new }

  def mirrored(jobs, numbered, times: 2)
    mirror = FakeMirror.new
    slots = Kimera::Execution::MirrorSlots.new(jobs, connections: connections, numbered: numbered, mirror: mirror)
    Dir.mktmpdir do |root|
      execution = described_class.new(registry: nil, root: root, tests: [], jobs: jobs, slots: slots)
      times.times { execution.__send__(:with_mirror) { |mirror| expect(File.directory?(mirror)).to(be(true)) } }
    end
    numbered.prepared
  end

  it "closes the parent's connections before every mirror, and prepares each slot's database once" do
    expect(mirrored(3, FakeNumbered.new)).to(eq([1, 2]))
    expect(connections.released).to(eq(2))
  end

  it "prepares nothing for one mirror at a time, or a database.yml with no TEST_ENV_NUMBER" do
    expect(mirrored(1, FakeNumbered.new)).to(eq([]))
    expect(mirrored(2, FakeNumbered.new(numbered: false))).to(eq([]))
  end
end
