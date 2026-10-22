# frozen_string_literal: true

require "fileutils"
require "tmpdir"

# Sinatra's integration tests start servers and stop them in teardown (#16).
# A warm worker the watchdog kills mid-test never runs that teardown, and
# the servers outlived the run, holding their ports.
RSpec.describe("processes a test starts") do
  def scaffold(fixture)
    FileUtils.mkdir_p(File.join(fixture, "app"))
    FileUtils.mkdir_p(File.join(fixture, "spec"))
    # Deleting the push hangs the loop, and the worker running it.
    File.write(File.join(fixture, "app", "countdown.rb"), <<~RUBY)
      # frozen_string_literal: true
      class Countdown
        def run(limit)
          ticks = []
          while ticks.size < limit
            ticks.push(:tick)
            Thread.pass
          end
          ticks.size
        end
      end
    RUBY
    # The "server" holds a shared lock on server.lock for as long as it lives.
    File.write(File.join(fixture, "spec", "countdown_spec.rb"), <<~RUBY)
      # frozen_string_literal: true
      require_relative "../app/countdown"

      RSpec.describe Countdown do
        before do
          @lock = File.open(File.expand_path("../server.lock", __dir__), File::CREAT | File::WRONLY)
          @lock.flock(File::LOCK_SH)
          @server = Process.spawn("sleep", "600", out: @lock, err: File::NULL)
          File.write(File.expand_path("../servers.txt", __dir__), "\#{@server}\\n", mode: "a")
        end

        after do
          Process.kill("KILL", @server)
          Process.wait(@server)
          @lock.close
        end

        it { expect(Countdown.new.run(3)).to eq(3) }
      end
    RUBY
  end

  def released?(path)
    File.open(path) do |lock|
      50.times do
        return true if lock.flock(File::LOCK_EX | File::LOCK_NB)
        sleep(0.1)
      end
    end
    false
  end

  # Only if the fix is missing: don't leave its servers running.
  def stop(servers)
    File.readlines(servers).each { |pid| stop!(Integer(pid)) } if File.exist?(servers)
  end

  def stop!(pid)
    Process.kill("KILL", pid)
  rescue Errno::ESRCH
    nil
  end

  # The run, and whether every server it started was gone once it ended.
  def warm_run
    Dir.mktmpdir("kimera-process-group") do |fixture|
      scaffold(fixture)
      run = test_outcome(cwd: fixture, arguments: %w[--soft-timeout 30 --hard-timeout 1])
      [run, released?(File.join(fixture, "server.lock"))]
    ensure
      stop(File.join(fixture, "servers.txt"))
    end
  end

  it "go with a warm worker the watchdog kills", :aggregate_failures do
    run, released = warm_run
    statuses = run.results.to_h { |row| [row["label"], row["status"]] }
    expect(statuses).to(include("delete `ticks.push(:tick)`" => "timeout"), run.output)
    expect(released).to(be(true), "a server outlived the run")
  end
end
