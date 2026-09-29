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

  it "still shuts down when the parent is no longer listening" do
    duty = duty()
    duty.pipes.res_r.close
    expect { duty.finish(database, RuntimeError.new("boom")) }.not_to(raise_error)
  end
end
