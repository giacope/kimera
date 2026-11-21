# frozen_string_literal: true

class Lifeline
  ROOT = Process.pid

  def initialize(root = ROOT)
    @root = root
  end

  def hold
    sleep(0.1) while alive?
  end

  def watch = Thread.new { hold.then { exit!(1) } }

  def shell = "while kill -0 #{@root} 2>/dev/null; do sleep 0.1; done"

  def command = ["sh", "-c", shell]

  private

  def alive?
    Process.kill(0, @root)
  rescue Errno::ESRCH
    false
  end
end

module Forks
  def _fork
    super.tap { |pid| Lifeline.new.watch if pid.zero? }
  end
end

Process.singleton_class.prepend(Forks)
