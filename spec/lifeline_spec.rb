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

  def rooted
    reader, writer = IO.pipe
    loader = root(reader, writer)
    reader.close
    held = waiter(loader, writer)
    Process.detach(held)
    yield(held, writer)
  ensure
    writer.close unless writer.closed?
    stop(held)
  end

  def waiter(loader, writer)
    fork do
      writer.close
      Lifeline.new(loader).hold
      exit!(0)
    end
  end

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
end
