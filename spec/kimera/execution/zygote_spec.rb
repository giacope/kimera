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
    expect { zygote.call { raise(ArgumentError, "bad") } }
      .to(raise_error(described_class::Raised, "bad") { |error| expect(error.kind).to(eq("ArgumentError")) })
  end

  it "brings back the child's frames and headline with a raised error", :aggregate_failures do
    zygote.call { raise(ArgumentError, "bad") }
  rescue described_class::Raised => error
    expect(error.headline).to(eq("ArgumentError: bad"))
    expect(error.backtrace.first).to(include("zygote_spec.rb"))
  end

  it "keeps a soft timeout's frames too" do
    zygote.call { raise(Timeout::Error, "late") }
  rescue Timeout::Error => error
    expect(error.backtrace.first).to(include("zygote_spec.rb"))
  end

  it "brings back at most a screenful of frames" do
    deep = ->(n) { n.zero? ? raise(ArgumentError, "deep") : deep.call(n - 1) }
    zygote.call { deep.call(100) }
  rescue described_class::Raised => error
    expect(error.backtrace.size).to(eq(described_class::FRAMES))
  end

  it "reports a child that exits without replying, with its status", :aggregate_failures do
    expect { zygote.call { exit!(3) } }
      .to(raise_error(described_class::Died, "") { |died| expect([died.code, died.signal]).to(eq([3, nil])) })
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

  it "ignores SIGQUIT here while the child runs, and hands the child the handler" do
    previous = Signal.trap("QUIT") { :dumped }
    during = zygote.call { Signal.trap("QUIT", "DEFAULT").class.name }
    expect([during, Signal.trap("QUIT", previous).class]).to(eq(["Proc", Proc]))
  end

  describe "the reply, read in this process" do
    it "reports a signal the block raised as the child's death" do
      expect { InlineZygote.new.call { raise(SignalException, "TERM") } }
        .to(raise_error(described_class::Died, /\ASignalException: SIGTERM/))
    end

    it "lets an interrupt through, so ^C still stops the run" do
      expect { InlineZygote.new.call { raise(Interrupt) } }.to(raise_error(Interrupt))
    end
  end

  # The child's half runs only in a forked child, where no coverage reaches;
  # run it here, with its exit stubbed.
  describe "the child's half, run here" do
    # A zygote whose child half ran here with its exit stubbed, and its reply.
    def spawned(saved)
      reader, writer = IO.pipe
      zygote = described_class.new.tap { |stubbed| allow(stubbed).to(receive(:exit!)) }
      zygote.__send__(:spawned, described_class::Pipe.new(reader.dup, writer), saved) { 7 }
      [zygote, reader.read]
    end

    it "hands back the caller's QUIT handler, replies, and exits without unwinding", :aggregate_failures do
      handler = proc {}
      previous = Signal.trap("QUIT", "IGNORE")
      child, reply = spawned(handler)
      expect([Signal.trap("QUIT", previous), JSON.parse(reply)]).to(eq([handler, { "value" => 7 }]))
      expect(child).to(have_received(:exit!).with(0))
    end
  end

  describe described_class::Pipe do
    def pipe
      reader, writer = IO.pipe
      [described_class.new(reader.dup, writer), reader]
    end

    it "posts the reply and closes both of the child's ends", :aggregate_failures do
      pipe, reader = pipe()
      pipe.post("reply")
      expect(reader.read).to(eq("reply"))
      expect([pipe.reader, pipe.writer]).to(all(be_closed))
    end

    it "takes the reply and closes both of the parent's ends", :aggregate_failures do
      reader, writer = IO.pipe
      pipe = described_class.new(reader, writer.dup)
      writer.tap { |sink| sink.write("reply") }.close
      expect(pipe.take).to(eq("reply"))
      expect([pipe.reader, pipe.writer]).to(all(be_closed))
    end
  end
end
