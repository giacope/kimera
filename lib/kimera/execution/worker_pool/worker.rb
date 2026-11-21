# frozen_string_literal: true

require_relative "../child_process"

Kimera::Execution::WorkerPool::Worker =
  Struct.new(:pid, :request, :response, :inflight, :deadline, :slot, :stacks, :last_words, :unread) do
    include Kimera::Execution::ChildProcess
    private(*members)
    def feed(chunk, &)
      *complete, partial = (rest + chunk).split("\n", -1)
      self.unread = partial
      complete.each(&)
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

    def claim(id, due)
      busy!(id)
      renew(due)
    end

    def autopsy
      Array(stacks&.take(pid))
    end

    def halt
      autopsy.tap { kill(pid) }
    end

    def renew(due)
      self.deadline = due
    end

    def expired?(now)
      deadline && !(deadline - now).positive?
    end

    def retire(due)
      self.inflight = nil
      renew(due)
      request
    end

    def heard(message, due)
      renew(due)
      self.last_words = message["detail"] if message["t"] == "crash"
      self
    end

    def obituary(status)
      words = [demise(status), last_words].compact
      words.empty? ? [] : [words.join("\n")]
    end

    def demise(status)
      return unless status
      signal = status.termsig
      signal ? "died on signal #{signal} (SIG#{Signal.signame(signal)})" : "exited #{status.exitstatus}"
    end

    def trace(listeners, id) = listeners.traced(slot, id)

    def forfeit
      yield(inflight) if inflight
    end

    def inform(guard, status) = guard.track(status, last_words)

    def disconnect
      shut(response)
      shut(request)
    end

    def buried = bury(pid)

    def dismiss
      disconnect
      stop(pid)
    end

    def offer(id)
      request.puts(JSON.generate(id: id))
    rescue Errno::EPIPE, IOError
      nil
    end
  end
