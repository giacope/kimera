# frozen_string_literal: true

class Kimera::CLI::Run::Streams
  def initialize(output = $stdout, errors = $stderr)
    @output = output
    @errors = errors
  end

  def standard?(io) = io.equal?(@output)

  def divert = @output.reopen(@errors)
end
