# frozen_string_literal: true

module ProcessStatuses
  module_function

  def exited(code) = Process.wait2(Process.spawn("sh", "-c", "exit #{code}")).last

  def killed(signal)
    pid = Process.spawn("sleep", "30")
    Process.kill(signal, pid)
    Process.wait2(pid).last
  end
end
