# frozen_string_literal: true

require "json"
require "kimera/execution/pool_driver"

# A worker ending on an exception tells the parent why before its pipe closes,
# so the crash verdict can say more than "crashed".
RSpec.describe(Kimera::Execution::Pool::Duty) do
  let(:database) { Class.new { def before_exit(index) = index }.new }

  def duty
    request, response = Array.new(2) { IO.pipe }
    described_class.new(:serve, 0, Kimera::Execution::Pool::Channels.new(*request, *response))
  end

  it "sends the exception it dies of, then closes its end", :aggregate_failures do
    duty = duty()
    duty.finish(database, RuntimeError.new("boom"))
    message = JSON.parse(duty.pipes.res_r.read)
    expect(message).to(include("t" => "crash"))
    expect(message["detail"]).to(start_with("RuntimeError: boom"))
  end

  it "says nothing when it finishes normally" do
    duty = duty()
    duty.finish(database, nil)
    expect(duty.pipes.res_r.read).to(eq(""))
  end

  it "ticks before each covering test, so the parent's watchdog times one test at a time" do
    duty = duty()
    duty.pulse
    duty.finish(database, nil)
    expect(duty.pipes.res_r.read).to(eq("#{JSON.generate(t: "tick")}\n"))
  end

  it "retires by finishing, then dying the way the test process it ran died", :aggregate_failures do
    duty = duty()
    pid = fork { duty.retire(database, Kimera::Execution::Zygote::Died.new("SIGTERM in t1", code: 3)) }
    duty.pipes.res_w.close
    expect(JSON.parse(duty.pipes.res_r.read)).to(include("t" => "crash", "detail" => "SIGTERM in t1"))
    expect(Process.wait2(pid).last.exitstatus).to(eq(3))
  end

  it "still shuts down when the parent is no longer listening" do
    duty = duty()
    duty.pipes.res_r.close
    expect { duty.finish(database, RuntimeError.new("boom")) }.not_to(raise_error)
  end

  it "sends a dead test process's own words, not the exception carrying them" do
    duty = duty()
    duty.finish(database, Kimera::Execution::Zygote::Died.new("SIGTERM in t1"))
    expect(JSON.parse(duty.pipes.res_r.read)).to(include("detail" => "SIGTERM in t1"))
  end

  # Retires a duty on +error+ in a fork that exits 99 if it lives on: what the duty said, and how the fork ended.
  def retired(error)
    duty = duty()
    pid =
      fork do
        duty.retire(database, error)
      ensure
        exit!(99)
      end
    duty.pipes.res_w.close
    [JSON.parse(duty.pipes.res_r.read), Process.wait2(pid).last]
  end

  it "exits with the code the test process it ran exited with, after saying why", :aggregate_failures do
    message, status = retired(Kimera::Execution::Zygote::Died.new("gone", code: 3))
    expect(message).to(include("t" => "crash", "detail" => "gone"))
    expect(status.exitstatus).to(eq(3))
  end

  it "exits 1 for a test process that died with no code" do
    _, status = retired(Kimera::Execution::Zygote::Died.new("gone"))
    expect(status.exitstatus).to(eq(1))
  end

  it "dies of the signal the test process it ran died of" do
    _, status = retired(Kimera::Execution::Zygote::Died.new("killed", signal: 15))
    expect([status.signaled?, status.termsig]).to(eq([true, 15]))
  end

  it "lives on after an error that is not a test process's death" do
    _, status = retired(RuntimeError.new("boom"))
    expect(status.exitstatus).to(eq(99))
  end
end
