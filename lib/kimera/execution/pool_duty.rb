# frozen_string_literal: true

require "json"
require_relative "fault"
require_relative "last_words"
require_relative "zygote"

module Kimera
  module Execution
  end
end

class Kimera::Execution::Pool; end

using Kimera::Execution::Fault

Kimera::Execution::Pool::Duty =
  Struct.new(:entry, :index, :pipes) do
    def run(shift)
      shift.public_send(entry, pipes.req_r, pipes.res_w)
    end

    def pulse
      pipes.res_w.puts(JSON.generate(t: "tick"))
    end

    def retire(database, error)
      finish(database, error)
      echo(error)
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

    def echo(error) = error&.echo(self)

    def die_of(signal)
      Signal.trap(signal, "SYSTEM_DEFAULT")
      Process.kill(signal, Process.pid)
    end

    def exit_with(code) = exit!(code)

    def words(error) = error ? error.last_words : ""
  end
