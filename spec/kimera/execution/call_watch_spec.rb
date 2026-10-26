# frozen_string_literal: true

require "kimera/execution/call_watch"
require "kimera/runtime"

# The reload tier bakes one mutant into a fresh process; the watch tells it
# which tests call the method that holds the mutant (R6B1-M4).
RSpec.describe(Kimera::Execution::CallWatch) do
  let(:source) do
    <<~RUBY
      class Watched
        def outer
          def inner(a) = @inner ||= a + 1
          @outer ||= [1].map { |x| x * 2 }
        end

        def other = 3
      end
    RUBY
  end

  def watched(line) = described_class.new(source, line, 7)

  it "calls the probe first in the innermost method that holds the line, on the lines it had", :aggregate_failures do
    probe = "::Kimera::RUNTIME.active?(7)"
    expect(watched(4).source).to(eq(source.sub("def outer\n", "def outer; #{probe}\n")))
    expect(watched(3).source).to(eq(source.sub("= @inner ||= a + 1\n", "= (#{probe}; @inner ||= a + 1)\n")))
  end

  it "leaves the source unwatched when the probed text would not parse" do
    allow(Kimera::GuardProbe).to(receive(:new).and_return(instance_double(Kimera::GuardProbe, watch: [[0, 0, "("]])))
    expect([watched(4).source, watched(4).watching?, watched(4).reached?([])]).to(eq([source, false, true]))
  end

  # Outside any method it cannot tell, so every test counts as reaching it.
  it "leaves a line no method holds as it is", :aggregate_failures do
    expect([watched(1).source, watched(1).watching?, watched(1).reached?([])]).to(eq([source, false, true]))
    expect([watched(4).watching?, watched(4).reached?(nil), watched(4).reached?([3, 7])]).to(eq([true, false, true]))
  end

  def touched(held, name)
    ledger = Kimera::RUNTIME.start!
    held.public_send(name)
    Kimera::RUNTIME.stop!(ledger)
  end

  it "records the mutant each time its method is called, and not otherwise" do
    held = Module.new.tap { |mod| mod.module_eval(watched(4).source) }.const_get(:Watched).new
    expect([touched(held, :other), touched(held, :outer), touched(held, :outer)]).to(eq([[], [7], [7]]))
  end
end
