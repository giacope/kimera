# frozen_string_literal: true

require "kimera/execution/isolated"
require "tmpdir"

# Without numbered databases, concurrent mirrors past the first take copies
# of the parent's prepared database, made once before the first mirror.
RSpec.describe(Kimera::Execution::IsolatedExecution) do
  let(:mirror) { instance_double(Kimera::Execution::MirrorDatabase, prepare: nil) }

  before do
    parent = instance_double(Kimera::Execution::ParentConnections, release!: nil)
    allow(Kimera::Execution::ParentConnections).to(receive(:new).and_return(parent))
    allow(Kimera::Execution::MirrorDatabase).to(receive(:new).with(nil).and_return(mirror))
  end

  def mirrored(jobs, numbered: false)
    numbers = instance_double(Kimera::Execution::NumberedDatabases, numbered?: numbered, prepare: nil)
    allow(Kimera::Execution::NumberedDatabases).to(receive(:new).and_return(numbers))
    Dir.mktmpdir do |root|
      execution = described_class.new(registry: nil, root: root, tests: [], jobs: jobs)
      allow(execution).to(receive(:plan).and_return(instance_double(Kimera::Execution::IsolatedPlan, root: root)))
      2.times { execution.__send__(:with_mirror, &:itself) }
    end
  end

  it "copies the parent's database once for the mirrors past the first" do
    mirrored(3)
    expect(mirror).to(have_received(:prepare).with(1...3).once)
  end

  it "copies nothing for numbered databases" do
    mirrored(3, numbered: true)
    expect(mirror).not_to(have_received(:prepare))
  end
end
