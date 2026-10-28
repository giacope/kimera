# frozen_string_literal: true

module Kimera
  class CLI
  end
end

class Kimera::CLI::SuiteSignal
  def initialize(status)
    @status = status
  end

  killed = "the suite was killed by SIG%s before it printed a summary%s"
  hints = { "KILL" => " — out of memory?" }.freeze
  define_method(:diagnosis) do
    signal = status.termsig if status.respond_to?(:termsig)
    name = Signal.signame(signal) if signal
    format(killed, name, hints[name]) if name
  end

  private

  attr_reader :status
end
