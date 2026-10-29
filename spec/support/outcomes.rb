# frozen_string_literal: true

require "kimera/cli/outcome"

# What exe/kimera does with a command's outcome: it prints what the command
# said, then exits with the outcome's status. Here the exit writes the status
# down instead, and the status is the answer.
module Outcomes
  def ended(outcome, io = $stdout, errors = $stderr)
    exits = FakeExits.new
    outcome.print(io, errors).exit(exits)
    exits.codes.fetch(0)
  end
end

RSpec.configure { |config| config.include(Outcomes) }

# A command as exe/kimera drives it, for specs written against a run that
# prints and answers its status: each run prints the outcome to IO and ERRORS
# and answers the status. WORDS lead every run's arguments (a subcommand of
# Kimera::CLI, say).
class Driven
  include Outcomes

  def initialize(command, io, errors, *words)
    @command = command
    @io = io
    @errors = errors
    @words = words
  end

  def run(argv) = ended(@command.run([*@words, *argv]), @io, @errors)
end
