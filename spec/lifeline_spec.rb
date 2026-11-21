# frozen_string_literal: true

RSpec.describe(Lifeline) do
  def root(reader, writer)
    pid =
      fork do
        writer.close
        reader.read
        exit!(0)
      end
    Process.detach(pid)
    pid
  end

  def rooted(action = :hold.to_proc)
    reader, writer = IO.pipe
    loader = root(reader, writer)
    reader.close
    held = waiter(loader, writer, action)
    Process.detach(held)
    yield(held, writer)
  ensure
    writer.close unless writer.closed?
    stop(held)
  end

  def waiter(loader, writer, action)
    fork do
      writer.close
      action.call(Lifeline.new(loader))
      exit!(0)
    end
  end

  def spawning = ->(line) { system(*line.command) }

  def watching = ->(line) { line.watch.then { IO.pipe { |reader, _writer| reader.read } } }

  def stop(pid)
    Process.kill(:KILL, pid)
  rescue Errno::ESRCH
    nil
  end

  def running?(pid)
    Process.kill(0, pid).positive?
  rescue Errno::ESRCH
    false
  end

  def lives?(pid, within)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + within
    sleep(0.05) while running?(pid) && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
    running?(pid)
  end

  it "keeps a stand-in waiting while the process that loaded the specs lives" do
    expect(rooted { |held, _writer| lives?(held, 0.5) }).to(be(true))
  end

  it "ends a stand-in once the process that loaded the specs is gone" do
    expect(rooted { |held, writer| writer.close.then { lives?(held, 5) } }).to(be(false))
  end

  it "lets a process blocked on a pipe that never closes go on while the process that loaded the specs lives" do
    expect(rooted(watching) { |held, _writer| lives?(held, 0.5) }).to(be(true))
  end

  it "ends that process once the process that loaded the specs is gone" do
    expect(rooted(watching) { |held, writer| writer.close.then { lives?(held, 5) } }).to(be(false))
  end

  it "keeps the shell stand-in waiting while the process that loaded the specs lives" do
    expect(rooted(spawning) { |held, _writer| lives?(held, 0.5) }).to(be(true))
  end

  it "ends the shell stand-in once the process that loaded the specs is gone" do
    expect(rooted(spawning) { |held, writer| writer.close.then { lives?(held, 5) } }).to(be(false))
  end
end
