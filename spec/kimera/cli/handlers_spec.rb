# frozen_string_literal: true

require "kimera/cli/handlers"

RSpec.describe(Kimera::CLI::Handlers) do
  # A fresh process that has not loaded the completion handler: whether it is
  # defined before a run, and the run's status.
  def fresh
    fresh_lines(<<~RUBY)
      require "kimera/cli"
      require "stringio"
      before = defined?(Kimera::CLI::Completion).inspect
      puts(before, Kimera::CLI::Handlers.new(StringIO.new, StringIO.new).run("workflows", :Completion, ["bash"]))
    RUBY
  end

  it "loads a handler's file before running it" do
    expect(fresh).to(eq(%w[nil 0]))
  end
end
