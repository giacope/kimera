# frozen_string_literal: true

require_relative "outcome"

class Kimera::CLI::Checklist
  def initialize(io)
    @io = io
  end

  def shown(check)
    status, text = check
    @io.puts("#{status} #{text}")
    @io.flush
    self
  end
end
