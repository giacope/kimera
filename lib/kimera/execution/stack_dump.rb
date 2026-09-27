# frozen_string_literal: true

module Kimera
  module Execution
  end
end

class Kimera::Execution::StackDump
  SIGNAL = "QUIT"
  GRACE = 1.0
  POLL = 0.02
  MAX_THREADS = 8
  MAX_FRAMES = 12
  HARNESS = File.expand_path("..", __dir__)
  HEADER = "threads in the worker when it was killed:"
  PAUSE = Kernel.method(:sleep)
  CLOCK = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
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
    Process.kill(SIGNAL, pid)
    collect(path(pid))
  rescue Errno::ESRCH
    nil
  end

  private

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
    shown = frames.first(MAX_FRAMES).map { |frame| "  #{frame.delete_prefix("#{Dir.pwd}/")}" }
    ["#{label(thread)} (#{thread.status || "dead"}):", *shown, *more(frames.size - MAX_FRAMES, "  … %d more frame(s)")]
      .join("\n")
  end

  def more(hidden, text) = hidden.positive? ? [format(text, hidden)] : []

  def own(frames)
    frames.drop_while { |frame| frame.start_with?(__FILE__) }.take_while { |frame| !frame.start_with?(HARNESS) }
  end

  def label(thread)
    return "main thread" if thread == Thread.main
    "thread #{thread.name || thread.object_id}"
  end
end
