# frozen_string_literal: true

module Kimera
  class CLI
  end
end

Kimera::CLI::SuiteSignal =
  Data.define(:status) do
    killed = "the suite was killed by SIG%s before it printed a summary%s"
    hints = { "KILL" => " — out of memory?" }.freeze
    define_method(:diagnosis) do
      signal = status.termsig if status.respond_to?(:termsig)
      name = Signal.signame(signal) if signal
      format(killed, name, hints[name]) if name
    end
  end
