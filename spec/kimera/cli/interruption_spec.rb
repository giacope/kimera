# frozen_string_literal: true

require "kimera/cli/interruption"
require "stringio"

# R4-KR2: Ctrl-C printed an Interrupt backtrace from rubygems.
RSpec.describe(Kimera::CLI::Interruption) do
  let(:errors) { StringIO.new }

  it "answers what the command answers" do
    expect(described_class.new(errors).guard { 2 }).to(eq(2))
  end

  it "says it was interrupted, and exits as the shell would", :aggregate_failures do
    expect(described_class.new(errors).guard { raise(Interrupt) }).to(eq(130))
    expect(described_class.new(errors).guard { raise(SignalException, "TERM") }).to(eq(143))
    expect(errors.string).to(
      eq(
        "kimera: interrupted (SIGINT); the test processes it started are stopped\n" \
          "kimera: interrupted (SIGTERM); the test processes it started are stopped\n"
      )
    )
  end

  it "lets the signal through in a process kimera forked" do
    expect { described_class.new(errors, Process.pid + 1).guard { raise(Interrupt) } }.to(raise_error(Interrupt))
  end
end
