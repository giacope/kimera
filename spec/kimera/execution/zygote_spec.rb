# frozen_string_literal: true

require "kimera/execution/zygote"

RSpec.describe(Kimera::Execution::Zygote) do
  subject(:zygote) { described_class.new }

  it "returns what the block returns in its own process, as JSON brings it back" do
    expect(zygote.call { { "pid" => Process.pid, "ids" => [1, 2] } }).to(include("ids" => [1, 2]))
  end

  it "runs the block in another process" do
    expect(zygote.call { Process.pid }).not_to(eq(Process.pid))
  end

  it "keeps the block's side effects in the child" do
    store = { "warm" => false }
    zygote.call { store["warm"] = true }
    expect(store).to(eq("warm" => false))
  end

  it "raises a soft timeout in the child here as a Timeout::Error" do
    expect { zygote.call { raise(Timeout::Error, "late") } }.to(raise_error(Timeout::Error, "late"))
  end

  it "raises any other error here, naming its class", :aggregate_failures do
    expect { zygote.call { raise(ArgumentError, "bad") } }.to(
      raise_error(described_class::Raised, "bad") { |error| expect(error.kind).to(eq("ArgumentError")) }
    )
  end

  it "reports a child that exits without replying, with its status", :aggregate_failures do
    expect { zygote.call { exit!(3) } }.to(
      raise_error(described_class::Died, "") { |died| expect([died.code, died.signal]).to(eq([3, nil])) }
    )
  end

  it "reports a child killed by a signal, with the signal", :aggregate_failures do
    expect { zygote.call { Process.kill("KILL", Process.pid) } }
      .to(raise_error(described_class::Died) { |died| expect(died.signal).to(eq(9)) })
  end

  it "reports a signal nothing in the child trapped, with the advice and the signal", :aggregate_failures do
    expect { zygote.call { raise(SignalException, "TERM") } }.to(
      raise_error(described_class::Died, /\ASignalException: SIGTERM\nnothing trapped SIGTERM/) do |died|
        expect(died.signal).to(eq(15))
      end
    )
  end

  it "ignores SIGQUIT here while the child runs, and hands the child the handler", :aggregate_failures do
    previous = Signal.trap("QUIT") { :dumped }
    during = zygote.call { Signal.trap("QUIT", "DEFAULT").class.name }
    expect(during).to(eq("Proc"))
    expect(Signal.trap("QUIT", previous)).to(be_a(Proc))
  end
end
