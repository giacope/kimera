# frozen_string_literal: true

require "kimera/cli/interruption"
require "stringio"

RSpec.describe(Kimera::CLI::Interruption) do
  let(:errors) { StringIO.new }

  def answer(leader = Process.pid, &)
    ended(described_class.new(leader).guard(&), StringIO.new, errors)
  rescue SignalException => error
    error
  end

  it "answers what the command answers" do
    expect(answer { Kimera::CLI::Outcome::Ended.new(2) }).to(eq(2))
  end

  it "says it was interrupted, and exits as the shell would", :aggregate_failures do
    expect(answer { raise(Interrupt) }).to(eq(130))
    expect(answer { raise(SignalException, "TERM") }).to(eq(143))
    expect(errors.string).to(
      eq(
        "kimera: interrupted (SIGINT); the test processes it started are stopped\n" \
          "kimera: interrupted (SIGTERM); the test processes it started are stopped\n"
      )
    )
  end

  it "lets the signal through in a process kimera forked" do
    expect(answer(Process.pid + 1) { raise(Interrupt) }).to(be_a(Interrupt))
  end
end
