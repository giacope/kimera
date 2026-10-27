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

  let(:probe) { "::Kimera::RUNTIME.active?(7)" }

  def watched(text, held = source) = described_class.new(held, held.byteindex(text), 7)

  it "calls the probe first in the innermost method that holds the point, on the lines it had", :aggregate_failures do
    expect(watched("@outer").source).to(eq(source.sub("def outer\n", "def outer; #{probe}\n")))
    expect(watched("a + 1").source).to(eq(source.sub("= @inner ||= a + 1\n", "= (#{probe}; @inner ||= a + 1)\n")))
  end

  # R6B2-M2: a one-line def that starts later on the point's line held it, by line.
  it "probes the method that holds the point, not a one-line def beside it on its line", :aggregate_failures do
    meter = "def reading\n  @reading ||= Struct.new(:value) { def high? = value > 5 }.new(@x > 0 ? @x : 0)\nend\n"
    expect(watched("@x > 0", meter).source).to(eq(meter.sub("def reading\n", "def reading; #{probe}\n")))
    expect(watched("value > 5", meter).source).to(eq(meter.sub("= value > 5 }", "= (#{probe}; value > 5) }")))
  end

  it "leaves the source unwatched when the probed text would not parse" do
    allow(Kimera::GuardProbe).to(receive(:new).and_return(instance_double(Kimera::GuardProbe, watch: [[0, 0, "("]])))
    expect([watched("@outer").source, watched("@outer").watching?, watched("@outer").reached?([])]).to(
      eq([source, false, true])
    )
  end

  # Outside any method it cannot tell, so every test counts as reaching it.
  it "leaves a point no method holds as it is", :aggregate_failures do
    expect([watched("class").source, watched("class").watching?, watched("class").reached?([])]).to(
      eq([source, false, true])
    )
    expect([watched("@outer").watching?, watched("@outer").reached?(nil), watched("@outer").reached?([3, 7])]).to(
      eq([true, false, true])
    )
  end

  def touched(held, name)
    ledger = Kimera::RUNTIME.start!
    held.public_send(name)
    Kimera::RUNTIME.stop!(ledger)
  end

  it "records the mutant each time its method is called, and not otherwise" do
    held = Module.new.tap { |mod| mod.module_eval(watched("@outer").source) }.const_get(:Watched).new
    expect([touched(held, :other), touched(held, :outer), touched(held, :outer)]).to(eq([[], [7], [7]]))
  end
end
