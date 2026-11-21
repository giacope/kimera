# frozen_string_literal: true

module PoolTrace
  Step =
    Struct.new(:act, :w, :kind, :id, :reply, :offer) do
      def self.of(act, slot, kind: "", id: nil, reply: ["none"])
        new(act, slot, kind, id || 0, reply[0], reply[1] || 0)
      end
    end

  Recorder =
    Struct.new(:queue, :slots, :steps, :unassigned, :sent) do
      def log(act, slot, **fields) = steps << Step.of(act, slot, **fields).to_h

      def to_h = { queue: queue, slots: slots, steps: steps }
    end

  class << self
    attr_accessor :recorder

    def traced(slot, _id) = slot

    def record(queue, jobs)
      [Pool, Fleet, Requests].each(&:install)
      self.recorder = Recorder.new(queue, (0...jobs).to_a, [], [], ["none"])
      yield
    ensure
      self.recorder = nil
    end
  end

  module Pool
    def self.install = Kimera::Execution::WorkerPool.prepend(self)

    def run
      super.tap { PoolTrace.recorder&.log("finish", -1) }
    rescue Kimera::Error
      PoolTrace.recorder&.log("abort", -1)
      raise
    end

    def assign(worker)
      trace = PoolTrace.recorder
      return super unless trace&.unassigned&.delete(worker)
      trace.sent = ["none"]
      super.tap { trace.log("spawn", worker.trace(PoolTrace, nil), reply: trace.sent) }
    end

    private

    def service(pipe)
      trace = PoolTrace.recorder
      return super unless trace
      worker = fleet[pipe]
      before = [trace.steps.size, worker.partial?]
      super.tap { trace.log("read", worker.trace(PoolTrace, nil), kind: "part") if started?(worker, *before) }
    end

    def deliver(worker, line)
      trace = PoolTrace.recorder
      return super unless trace
      message = parse(line) { return super }
      trace.sent = ["none"]
      slot = worker.trace(PoolTrace, nil)
      super.tap { trace.log("read", slot, kind: message["t"], id: message["id"], reply: trace.sent) }
    end

    def started?(worker, steps, partial)
      worker.partial? && (!partial || PoolTrace.recorder.steps.size > steps)
    end
  end

  module Fleet
    def self.install = Kimera::Execution::WorkerPool::Fleet.prepend(self)

    def remove(pipe, reason: :crash, stacks: [])
      worker = workers.fetch(pipe)
      act, kind = reason == :timeout ? ["expire", ""] : %w[read eof]
      held = nil
      worker.forfeit { |id| held = id }
      PoolTrace.recorder&.log(act, worker.trace(PoolTrace, nil), kind: kind, id: held)
      super
    end

    private

    def spawn
      super.tap { |worker| PoolTrace.recorder&.unassigned&.push(worker) }
    end
  end

  module Requests
    def self.install = Kimera::Execution::WorkerPool::Worker.prepend(self)

    def offer(id)
      PoolTrace.recorder&.sent = ["offer", id]
      super
    end

    def retire(due)
      PoolTrace.recorder&.sent = ["close"]
      super
    end

    def partial? = !unread.to_s.empty?
  end
end
