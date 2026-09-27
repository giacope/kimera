# frozen_string_literal: true

Kimera::Execution::WorkerPool::Worker =
  Struct.new(:pid, :request, :response, :inflight, :deadline, :slot, :stacks, :served) do
    def idle!
      self.inflight = nil
    end

    def busy!(id)
      self.inflight = id
    end

    def claim(id, limit)
      self.served = true
      busy!(id)
      renew(limit)
    end

    def fresh?
      !served
    end

    def autopsy
      stacks&.take(pid)
    end

    def halt
      autopsy.tap { Process.kill("KILL", pid) }
    rescue Errno::ESRCH
      nil
    end

    def renew(limit)
      self.deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + limit
    end

    def expired?(now)
      deadline && !(deadline - now).positive?
    end

    def retire
      self.inflight = nil
      self.deadline = nil
      request
    end

    def offer(id, recheck: false)
      request.puts(JSON.generate(recheck ? { id: id, recheck: true } : { id: id }))
    rescue Errno::EPIPE, IOError
      nil
    end
  end
