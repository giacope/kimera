# frozen_string_literal: true

# Real exit statuses, of processes that exit with a code or die of a signal.
module ProcessStatuses
  module_function

  def exited(code) = Process.wait2(Process.spawn("sh", "-c", "exit #{code}")).last

  def killed(signal)
    pid = Process.spawn("sleep", "30")
    Process.kill(signal, pid)
    Process.wait2(pid).last
  end
end
