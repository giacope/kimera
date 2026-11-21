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

  private

  def alive?
    Process.kill(0, @root)
  rescue Errno::ESRCH
    false
  end
end
