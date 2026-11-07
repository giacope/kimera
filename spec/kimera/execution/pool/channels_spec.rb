# frozen_string_literal: true

require "kimera/execution/pool_driver"

# Each side must close the pipe ends it doesn't own, or the reader never sees
# a worker exit.
RSpec.describe(Kimera::Execution::Pool::Channels) do
  # The request pipe's reader and writer, then the response pipe's.
  let(:ends) { Array.new(2) { IO.pipe }.flatten }
  let(:pipes) { described_class.new(*ends) }

  after { ends.each { |io| io.close unless io.closed? } }

  def closed = ends.map(&:closed?)

  it "closes the child's ends and hands back the parent's", :aggregate_failures do
    expect(pipes.parent!).to(eq(ends.values_at(1, 2)))
    expect(closed).to(eq([true, false, false, true]))
  end

  it "closes the parent's ends in the child" do
    pipes.child!
    expect(closed).to(eq([false, true, true, false]))
  end

  it "serves a shift's errand on the child's ends" do
    shift = Class.new { def coverage(request, response) = [request, response] }.new
    expect(pipes.serve(shift, :coverage)).to(eq(ends.values_at(0, 3)))
  end

  it "answers on the child's response end, then closes it", :aggregate_failures do
    pipes.say("tick")
    pipes.close
    expect([ends[2].read, closed]).to(eq(["tick\n", [false, false, false, true]]))
  end
end
