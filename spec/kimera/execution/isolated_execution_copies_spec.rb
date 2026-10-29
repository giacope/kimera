# frozen_string_literal: true

require "kimera/execution/isolated"
require "tmpdir"

# Without numbered databases, concurrent mirrors past the first take copies
# of the parent's prepared database, made once before the first mirror.
RSpec.describe(Kimera::Execution::IsolatedExecution) do
  # The slots the mirror database was prepared for over two mirrors of +jobs+.
  def mirrored(jobs, numbered: false)
    mirror = FakeMirror.new
    numbers = FakeNumbered.new(numbered: numbered)
    connections = FakeConnections.new
    slots = Kimera::Execution::MirrorSlots.new(jobs, connections: connections, numbered: numbers, mirror: mirror)
    Dir.mktmpdir do |root|
      execution = described_class.new(registry: nil, root: root, tests: [], jobs: jobs, slots: slots)
      2.times { execution.__send__(:with_mirror, &:itself) }
    end
    mirror.prepared
  end

  it "copies the parent's database once for the mirrors past the first" do
    expect(mirrored(3)).to(eq([1...3]))
  end

  it "copies nothing for numbered databases" do
    expect(mirrored(3, numbered: true)).to(eq([]))
  end
end
