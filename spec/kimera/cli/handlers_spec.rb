# frozen_string_literal: true

require "kimera/cli/handlers"
require "pathname"
require "stringio"
require "tmpdir"

RSpec.describe(Kimera::CLI::Handlers) do
  # A fresh process that has not loaded the completion handler: whether it is
  # defined before a run, and the run's status.
  def fresh
    fresh_lines(<<~RUBY)
      require "kimera/cli"
      require "stringio"
      before = defined?(Kimera::CLI::Completion).inspect
      outcome = Kimera::CLI::Handlers.new(StringIO.new, StringIO.new).run("workflows", :Completion, ["bash"])
      puts(before)
      outcome.print(StringIO.new, StringIO.new).exit(Class.new { def exit(code) = puts(code) }.new)
    RUBY
  end

  # A handler file nothing has loaded, in DIR, named as the handlers name theirs: relative to lib/kimera/cli.
  def late_handler(dir)
    path = File.join(dir, "late_handler.rb")
    File.write(path, "class Kimera::CLI::LateHandler\n  def initialize(**) = nil\n\n  def run(argv) = argv.size\nend\n")
    Pathname(path).relative_path_from(Pathname(File.expand_path("../../../lib/kimera/cli", __dir__))).to_s
  end

  it "loads a handler's file before running it" do
    expect(fresh).to(eq(%w[nil 0]))
  end

  # The handler's class is stubbed bare, so it is gone after the example; its file gives it what it answers.
  it "requires the handler's file in this process, then runs the class it defines" do
    stub_const("Kimera::CLI::LateHandler", Class.new)
    Dir.mktmpdir do |dir|
      expect(described_class.new(StringIO.new, StringIO.new).run(late_handler(dir), :LateHandler, %w[a b])).to(eq(2))
    end
  end
end
