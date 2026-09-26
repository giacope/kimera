# frozen_string_literal: true

require "kimera/execution/worker_pool"

RSpec.describe Kimera::Execution::WorkerPool::Worker do
  context "without a deadline" do
    it "never expires" do
      expect(described_class.new.expired?(10.0)).to(be_nil)
    end
  end

  context "with a deadline" do
    subject(:worker) { described_class.new(deadline: 10.0) }

    it "expires exactly when no positive interval remains", :aggregate_failures do
      expect(worker.expired?(9.9)).to(be(false))
      expect(worker.expired?(10.0)).to(be(true))
      expect(worker.expired?(10.1)).to(be(true))
    end
  end
end
