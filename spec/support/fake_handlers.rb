# frozen_string_literal: true

# The command handlers of the CLI, as Kimera::CLI::Handlers loads them: each
# run writes down the handler's file, its name and the arguments, and answers
# an outcome with the status it was given.
class FakeHandlers
  attr_reader :ran

  def initialize(status = 0)
    @status = status
    @ran = []
  end

  def run(file, name, argv)
    @ran.push([file, name, argv])
    Kimera::CLI::Outcome::Ended.new(@status)
  end

  def guard(leader) = Kimera::CLI::Interruption.new(leader)

  def help = Kimera::CLI::Outcome::Said.new(Kimera::HelpText.new)
end
