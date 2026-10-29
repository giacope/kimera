# frozen_string_literal: true

module Kimera
end

class Kimera::CLI
end

class Kimera::CLI::Handlers
  def initialize(io, errors)
    @io = io
    @errors = errors
  end

  def run(file, name, argv)
    require_relative(file)
    Kimera::CLI.const_get(name).new(io: @io, errors: @errors).run(argv)
  end
end
