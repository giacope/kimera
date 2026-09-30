# frozen_string_literal: true

# Logs the real parent's steps as the transitions of formal/WorkerPool.tla
# they should be, for TraceCheck to validate with formal/WorkerPoolTrace.tla
# (see formal/README.md). The hooks are prepended by `record`, which the
# property specs call inside the supervised fork: the classes in the test
# process itself are never touched.
module PoolTrace
  Step =
    Struct.new(:act, :w, :kind, :id, :reply, :offer, :recheck) do
      def self.of(act, slot, kind: "", id: nil, reply: ["none"])
        new(act, slot, kind, id || 0, reply[0], reply[1] || 0, reply[2] || false)
      end
    end

  # One run's steps, with the offer or close the step in progress sent.
  Recorder =
    Struct.new(:queue, :slots, :steps, :unassigned, :sent) do
      def log(act, slot, **fields) = steps << Step.of(act, slot, **fields).to_h

      def to_h = { queue: queue, slots: slots, steps: steps }
    end

  class << self
    attr_accessor :recorder

    def record(queue, jobs)
      [Pool, Fleet, Requests].each(&:install)
      self.recorder = Recorder.new(queue, (0...jobs).to_a, [], [], ["none"])
      yield
    ensure
      self.recorder = nil
    end
  end

  # WorkerPool: dispatching a line, the start of a line kept, the loop's end.
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
      super.tap { trace.log("spawn", worker.slot, reply: trace.sent) }
    end

    private

    def service(pipe)
      trace = PoolTrace.recorder
      return super unless trace
      worker = fleet.fetch(pipe)
      before = [trace.steps.size, partial?(worker)]
      super.tap { trace.log("read", worker.slot, kind: "part") if started?(worker, *before) }
    end

    def deliver(worker, line)
      trace = PoolTrace.recorder
      message = trace && parse(line)
      return super unless message
      trace.sent = ["none"]
      super.tap { trace.log("read", worker.slot, kind: message["t"], id: message["id"], reply: trace.sent) }
    end

    def partial?(worker) = !worker.unread.to_s.empty?

    # A new line was started: nothing was buffered, or a line was dispatched
    # since (and so the buffered start before it was finished).
    def started?(worker, steps, partial)
      partial?(worker) && (!partial || PoolTrace.recorder.steps.size > steps)
    end
  end

  # Fleet: spawns (logged with their first offer, by Pool#assign) and removals.
  module Fleet
    def self.install = Kimera::Execution::WorkerPool::Fleet.prepend(self)

    def remove(pipe, reason: :crash, stacks: nil)
      worker = workers.fetch(pipe)
      act, kind = reason == :timeout ? ["expire", ""] : %w[read eof]
      PoolTrace.recorder&.log(act, worker.slot, kind: kind, id: worker.inflight)
      super
    end

    private

    def spawn
      super.tap { |worker| PoolTrace.recorder&.unassigned&.push(worker) }
    end
  end

  # Worker: what the parent sends a child.
  module Requests
    def self.install = Kimera::Execution::WorkerPool::Worker.prepend(self)

    def offer(id, recheck: false)
      PoolTrace.recorder&.sent = ["offer", id, recheck]
      super
    end

    def retire(limit)
      PoolTrace.recorder&.sent = ["close"]
      super
    end
  end
end
