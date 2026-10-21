# frozen_string_literal: true

require "kimera/execution/isolated"
require "tmpdir"

# K3-4/K3-5: before a mirror starts, the parent lets go of its database
# connections and creates the numbered databases concurrent mirrors use.
RSpec.describe(Kimera::Execution::IsolatedExecution, :aggregate_failures) do
  let(:parent) { instance_double(Kimera::Execution::ParentConnections, release!: nil) }
  let(:numbered) { instance_double(Kimera::Execution::NumberedDatabases, numbered?: true, prepare: nil) }

  before do
    allow(Kimera::Execution::ParentConnections).to(receive(:new).and_return(parent))
    allow(Kimera::Execution::NumberedDatabases).to(receive(:new).and_return(numbered))
  end

  def mirrored(jobs, times: 2)
    Dir.mktmpdir do |root|
      execution = described_class.new(registry: nil, root: root, tests: [], jobs: jobs)
      allow(execution).to(receive(:plan).and_return(instance_double(Kimera::Execution::IsolatedPlan, root: root)))
      times.times { execution.__send__(:with_mirror) { |mirror| expect(File.directory?(mirror)).to(be(true)) } }
    end
  end

  it "closes the parent's connections before every mirror, and prepares each slot's database once" do
    mirrored(3)
    expect(parent).to(have_received(:release!).twice)
    expect(numbered).to(have_received(:prepare).with(1).once)
    expect(numbered).to(have_received(:prepare).with(2).once)
  end

  it "prepares nothing for one mirror at a time, or a database.yml with no TEST_ENV_NUMBER" do
    mirrored(1)
    expect(numbered).not_to(have_received(:prepare))
    allow(numbered).to(receive(:numbered?).and_return(false))
    mirrored(2)
    expect(numbered).not_to(have_received(:prepare))
  end
end
