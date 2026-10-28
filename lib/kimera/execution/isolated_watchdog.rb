# frozen_string_literal: true

require_relative "isolated_pulse"

module Kimera
  module Execution
  end
end

class Kimera::Execution::IsolatedWatchdog
  def initialize(limit, poll: 0.05)
    @limit = limit
    @poll = poll
  end

  def waitfor(pid, pulse = File::NULL, seconds = @limit)
    outlast(pid, Kimera::Execution::IsolatedPulse.new(pulse, seconds))
  rescue SignalException
    fail!(pid)
    raise
  end

  private

  def outlast(pid, watch)
    loop do
      watch = watch.observed
      step = attempt(pid, watch)
      return step unless step == :continue
    end
  end

  def attempt(pid, watch)
    done, status = Process.waitpid2(pid, Process::WNOHANG)
    return status.tap { kill(pid) } if done
    return fail!(pid) if watch.expired?
    pause
    :continue
  end

  def pause
    sleep(@poll)
  end

  def fail!(pid)
    kill(pid)
    reap(pid)
    :timeout
  end

  def kill(pid)
    Process.kill("KILL", -pid)
  rescue Errno::ESRCH, Errno::EPERM
    nil
  end

  def reap(pid)
    Process.waitpid(pid)
  rescue Errno::ECHILD
    nil
  end
end
