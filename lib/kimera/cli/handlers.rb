# frozen_string_literal: true

require_relative "help_text"
require_relative "interruption"
require_relative "outcome"

module Kimera
end

class Kimera::CLI
end

class Kimera::CLI::Handlers
  def initialize(io, errors, guard = Kimera::CLI::Interruption, help = Kimera::HelpText.new)
    @io = io
    @errors = errors
    @guard = guard
    @help = help
  end

  def run(file, name, argv)
    require_relative(file)
    Kimera::CLI.const_get(name).new(io: @io, errors: @errors).run(argv)
  end

  def guard(leader) = @guard.new(leader)

  def help = Kimera::CLI::Outcome::Said.new(@help)
end
