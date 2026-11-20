# frozen_string_literal: true

require "kimera/execution/pool_driver"

RSpec.describe(Kimera::Execution::Pool::Channels) do
  let(:ends) { Array.new(2) { IO.pipe }.flatten }
  let(:pipes) { described_class.new(*ends) }

  def piped
    yield
  ensure
    ends.each { |io| io.close unless io.closed? }
  end

  def closed = ends.map(&:closed?)

  it "closes the child's ends and hands back the parent's", :aggregate_failures do
    piped do
      expect(pipes.parent!).to(eq(ends.values_at(1, 2)))
      expect(closed).to(eq([true, false, false, true]))
    end
  end

  it "closes the parent's ends in the child" do
    piped do
      pipes.child!
      expect(closed).to(eq([false, true, true, false]))
    end
  end

  it "serves a shift's errand on the child's ends" do
    piped do
      shift = Class.new { def coverage(request, response) = [request, response] }.new
      expect(pipes.serve(shift, :coverage)).to(eq(ends.values_at(0, 3)))
    end
  end

  it "answers on the child's response end, then closes it", :aggregate_failures do
    piped do
      pipes.say("tick")
      pipes.close
      expect([ends[2].read, closed]).to(eq(["tick\n", [false, false, false, true]]))
    end
  end
end
