# frozen_string_literal: true

require_relative "frames"

module Kimera
  module Execution
  end
end

class Kimera::Execution::StackDump
  SIGNAL = "QUIT"
  GRACE = 1.0
  POLL = 0.02
  MAX_THREADS = 8
  HEADER = "threads in the worker when it was killed:"
  PAUSE = Kernel.method(:sleep)
  CLOCK = ->(reading = Process.clock_gettime(Process::CLOCK_MONOTONIC)) { reading }
  UNANSWERED = "no backtraces: the worker did not answer SIG#{SIGNAL} within #{GRACE}s " \
    "(blocked in native code without releasing the GVL?)".freeze

  def initialize(dir, pause: PAUSE, clock: CLOCK)
    @dir = dir
    @pause = pause
    @clock = clock
  end

  def arm!
    target = path(Process.pid)
    Signal.trap(SIGNAL) { write(target) }
  end

  def take(pid)
    ask(pid)
    [collect(path(pid))]
  rescue Errno::ESRCH
    []
  end

  private

  def ask(pid) = Process.kill(SIGNAL, leader?(pid) ? -pid : pid)

  def leader?(pid) = pid != Process.pid && Process.getpgid(pid) == pid

  def path(pid) = File.join(@dir, "#{pid}.txt")

  def collect(target)
    deadline = @clock.call + GRACE
    @pause.call(POLL) until File.exist?(target) || late?(deadline)
    consume(target)
  end

  def late?(deadline) = @clock.call >= deadline

  def consume(target)
    File.read(target, encoding: Encoding::UTF_8).scrub.tap { File.delete(target) }
  rescue Errno::ENOENT
    UNANSWERED
  end

  def write(target)
    staging = "#{target}.tmp"
    File.write(staging, render(Thread.list))
    File.rename(staging, target)
  end

  def render(threads)
    shown = threads.first(MAX_THREADS).map { |thread| describe(thread) }
    [HEADER, *shown, *more(threads.size - MAX_THREADS, "(%d more thread(s))")].join("\n")
  end

  def describe(thread)
    frames = own(Array(thread.backtrace))
    ["#{label(thread)} (#{thread.status || "dead"}):", *frames.lines, *more(frames.hidden, "  … %d more frame(s)")]
      .join("\n")
  end

  def more(hidden, text) = hidden.positive? ? [format(text, hidden)] : []

  def own(frames)
    outer = frames.drop_while { |frame| frame.start_with?(__FILE__) }
    Kimera::Execution::Frames.new(Kimera::Execution::Frames.new(outer).own)
  end

  def label(thread)
    return "main thread" if thread == Thread.main
    "thread #{thread.name || thread.object_id}"
  end
end
