# frozen_string_literal: true

require "kimera/cli/handlers"
require "open3"
require "rbconfig"

RSpec.describe(Kimera::CLI::Handlers) do
  # A fresh process that has not loaded the completion handler: whether it is
  # defined before a run, and the run's status.
  def fresh
    script = <<~RUBY
      require "kimera/cli"
      require "stringio"
      before = defined?(Kimera::CLI::Completion).inspect
      puts(before, Kimera::CLI::Handlers.new(StringIO.new, StringIO.new).run("workflows", :Completion, ["bash"]))
    RUBY
    root = File.expand_path("../../..", __dir__)
    Open3.capture2(RbConfig.ruby, "-rbundler/setup", "-Ilib", "-e", script, chdir: root).first
  end

  it "loads a handler's file before running it" do
    expect(fresh.lines(chomp: true)).to(eq(%w[nil 0]))
  end
end
