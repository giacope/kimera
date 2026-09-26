# frozen_string_literal: true

require "kimera/execution/pool_driver"

# Each side must close the pipe ends it doesn't own, or the reader never sees
# a worker exit.
RSpec.describe(Kimera::Execution::Pool::Channels) do
  def channels
    request, response = Array.new(2) { IO.pipe }
    described_class.new(*request, *response)
  end

  def shut(pipes)
    pipes.to_a.each { |io| io.close unless io.closed? }
  end

  it "closes the child's ends and hands back the parent's", :aggregate_failures do
    pipes = channels
    expect(pipes.parent!).to(eq([pipes.req_w, pipes.res_r]))
    expect([pipes.req_r.closed?, pipes.res_w.closed?]).to(eq([true, true]))
    expect([pipes.req_w.closed?, pipes.res_r.closed?]).to(eq([false, false]))
    shut(pipes)
  end

  it "closes the parent's ends in the child", :aggregate_failures do
    pipes = channels
    pipes.child!
    expect([pipes.req_w.closed?, pipes.res_r.closed?]).to(eq([true, true]))
    expect([pipes.req_r.closed?, pipes.res_w.closed?]).to(eq([false, false]))
    shut(pipes)
  end
end
