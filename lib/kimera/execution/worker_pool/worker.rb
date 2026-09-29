# frozen_string_literal: true

Kimera::Execution::WorkerPool::Worker =
  Struct.new(:pid, :request, :response, :inflight, :deadline, :slot, :stacks, :served, :last_words, :unread) do
    def lines(chunk)
      *complete, partial = (rest + chunk).split("\n", -1)
      self.unread = partial
      complete
    end

    def rest
      (unread || "".b).tap { self.unread = nil }
    end

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

    def retire(limit)
      self.inflight = nil
      renew(limit)
      request
    end

    def heard(message, limit)
      renew(limit)
      self.last_words = message["detail"] if message["t"] == "crash"
      self
    end

    def obituary(status)
      words = [demise(status), last_words].compact
      words.join("\n") unless words.empty?
    end

    def demise(status)
      return unless status
      signal = status.termsig
      signal ? "died on signal #{signal} (SIG#{Signal.signame(signal)})" : "exited #{status.exitstatus}"
    end

    def offer(id, recheck: false)
      request.puts(JSON.generate(recheck ? { id: id, recheck: true } : { id: id }))
    rescue Errno::EPIPE, IOError
      nil
    end
  end
