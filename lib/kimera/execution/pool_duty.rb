# frozen_string_literal: true

require "json"
require_relative "last_words"
require_relative "zygote"

module Kimera
  module Execution
  end
end

class Kimera::Execution::Pool; end

Kimera::Execution::Pool::Duty =
  Struct.new(:entry, :index, :pipes) do
    def run(shift)
      shift.public_send(entry, pipes.req_r, pipes.res_w)
    end

    def pulse
      pipes.res_w.puts(JSON.generate(t: "tick"))
    end

    def finish(database, error)
      confess(error) unless words(error).empty?
      database.before_exit(index)
      pipes.res_w.close
    end

    def confess(error)
      pipes.res_w.puts(JSON.generate(t: "crash", detail: words(error)))
    rescue IOError, SystemCallError
      nil
    end

    def echo(error)
      return unless error.is_a?(Kimera::Execution::Zygote::Died)
      signal = error.signal
      return exit!(error.code || 1) unless signal
      Signal.trap(signal, "SYSTEM_DEFAULT")
      Process.kill(signal, Process.pid)
    end

    def words(error)
      return "" unless error
      error.is_a?(Kimera::Execution::Zygote::Died) ? error.message : Kimera::Execution::LastWords.new(error).to_s
    end
  end
