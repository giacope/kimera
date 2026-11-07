# frozen_string_literal: true

require "kimera/cli/outcome"

module Outcomes
  def ended(outcome, io = $stdout, errors = $stderr)
    exits = FakeExits.new
    outcome.print(io, errors).exit(exits)
    exits.codes.fetch(0)
  end
end

RSpec.configure { |config| config.include(Outcomes) }

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
