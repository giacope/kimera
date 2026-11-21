# frozen_string_literal: true

require "kimera/execution/worker_pool"
require "timeout"

RSpec.describe(Kimera::Execution::WorkerPool) do
  def pool(queue:, spawner:, jobs: 1, deadline: 5.0)
    resolved = []
    lost = []
    resolve = ->(message) { resolved << message }
    loss = ->(id, reason, stacks) { lost << [id, reason, stacks] }
    listeners = described_class::Listeners.new(resolve: resolve, lost: loss, trace: nil)
    options = { jobs: jobs, hard_timeout: deadline }
    described_class.new(queue, spawner, listeners, options).run
    [resolved, lost]
  end

  def stacks = Object.new.tap { |taker| taker.define_singleton_method(:take) { |pid| ["stacks of #{pid}"] } }

  it "hands a timed-out worker's stacks to the loss" do
    worker = nil
    spawner = ->(_slot) { worker = forked { Lifeline.new.hold }.push(stacks) }
    _, lost = Timeout.timeout(10) { pool(queue: [1], spawner: spawner, deadline: 0.3) }
    expect(lost).to(eq([[1, :timeout, ["stacks of #{worker.first}"]]]))
  end

  describe "a crash" do
    def reaped
      yield
    ensure
      Process.waitall
    end

    def untouchable
      Object.new.tap do |never|
        never.define_singleton_method(:take) { |_pid| raise(ArgumentError, "a crash is never dumped") }
      end
    end

    it "is lost with how the worker died, never its stacks, even from an armed worker" do
      _, lost = reaped { pool(queue: [1], spawner: ->(_slot) { forked { exit!(1) }.push(untouchable) }) }
      expect(lost).to(eq([[1, :crash, ["exited 1"]]]))
    end
  end
end
