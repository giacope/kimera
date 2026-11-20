# frozen_string_literal: true

require "kimera/execution/zygote"
require "timeout"

RSpec.describe(Kimera::Execution::Zygote) do
  subject(:zygote) { described_class.new }

  let(:ending) do
    Class.new do
      def die_of(signal) = [:signal, signal]

      def exit_with(code) = [:exit, code]
    end.new
  end

  it "returns what the block returns in its own process, as JSON brings it back" do
    expect(zygote.call { { "pid" => Process.pid, "ids" => [1, 2] } }).to(include("ids" => [1, 2]))
  end

  it "hatches the block in another process at once, bringing back its value when asked", :aggregate_failures do
    reader, writer = IO.pipe
    collected = zygote.hatch { Process.pid.tap { writer.puts(it) } }
    started = Integer(reader.gets)
    expect([started == Process.pid, collected.call]).to(eq([false, started]))
  end

  def beside
    bystander = fork { sleep }
    yield
  ensure
    Process.kill("KILL", bystander)
    Process.wait(bystander)
  end

  it "keeps its pipe out of a process forked before the value is collected, which would hold the read open" do
    collected = zygote.hatch { 1 }
    expect(beside { Timeout.timeout(5) { collected.call } }).to(eq(1))
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
      raise_error(described_class::Raised, "bad") { |error| expect(error.headline).to(start_with("ArgumentError:")) }
    )
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
      .to(raise_error(described_class::Died, "") { |died| expect(died.echo(ending)).to(eq([:exit, 3])) })
  end

  it "reports a child killed by a signal, with the signal", :aggregate_failures do
    expect { zygote.call { Process.kill("KILL", Process.pid) } }
      .to(raise_error(described_class::Died) { |died| expect(died.echo(ending)).to(eq([:signal, 9])) })
  end

  it "reports a signal nothing in the child trapped, with the advice and the signal", :aggregate_failures do
    expect { zygote.call { raise(SignalException, "TERM") } }.to(
      raise_error(described_class::Died, /\ASignalException: SIGTERM\nnothing trapped SIGTERM/) do |died|
        expect(died.echo(ending)).to(eq([:signal, 15]))
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

  describe "the child's half" do
    def exits(writer)
      Object.new.tap do |exits|
        exits.define_singleton_method(:exit!) { |code| writer.puts(code) && Kernel.exit!(code) }
      end
    end

    it "replies and exits without unwinding", :aggregate_failures do
      reader, writer = IO.pipe
      value = described_class.new(exits(writer)).call { 7 }
      writer.close
      expect([value, reader.readlines(chomp: true)]).to(eq([7, ["0"]]))
    end
  end

  it "hands the child the caller's QUIT handler, which the caller ignores while it waits", :aggregate_failures do
    previous = Signal.trap("QUIT", proc {})
    seen = zygote.call { Signal.trap("QUIT", "IGNORE").class.name }
    expect([seen, Signal.trap("QUIT", previous).class]).to(eq(["Proc", Proc]))
  end

  describe described_class::Pipe do
    it "posts the reply and closes both of the child's ends", :aggregate_failures do
      reader, writer = IO.pipe
      ends = [reader.dup, writer]
      described_class.new(*ends).post("reply")
      expect(reader.read).to(eq("reply"))
      expect(ends).to(all(be_closed))
    end

    it "takes the reply and closes both of the parent's ends", :aggregate_failures do
      reader, writer = IO.pipe
      ends = [reader, writer.dup]
      writer.tap { |sink| sink.write("reply") }.close
      expect(described_class.new(*ends).take).to(eq("reply"))
      expect(ends).to(all(be_closed))
    end
  end
end
