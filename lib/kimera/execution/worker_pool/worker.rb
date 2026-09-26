# frozen_string_literal: true

Kimera::Execution::WorkerPool::Worker =
  Struct.new(:pid, :request, :response, :inflight, :deadline, :slot) do
    def idle!
      self.inflight = nil
    end

    def busy!(id)
      self.inflight = id
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

    def offer(id)
      request.puts(JSON.generate(id: id))
    rescue Errno::EPIPE, IOError
      nil
    end
  end
