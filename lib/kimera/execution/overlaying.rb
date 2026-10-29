# frozen_string_literal: true

require "monitor"

module Kimera
  module Execution
    class Overlaying
      def initialize(monitor = Monitor.new)
        @monitor = monitor
      end

      def overlay(&) = @monitor.synchronize(&)

      def overlaying? = @monitor.mon_locked?
    end

    OVERLAYING = Overlaying.new
    private_constant(:OVERLAYING)
  end
end
