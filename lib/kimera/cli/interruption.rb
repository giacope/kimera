# frozen_string_literal: true

module Kimera
  class CLI
  end
end

class Kimera::CLI::Interruption
  def initialize(errors, leader = Process.pid)
    @errors = errors
    @leader = leader
  end

  def guard
    yield
  rescue SignalException => error
    raise unless Process.pid == @leader
    said(error.signo)
  end

  private

  def said(signo)
    @errors.puts("kimera: interrupted (SIG#{Signal.signame(signo)}); the test processes it started are stopped")
    128 + signo
  end
end
