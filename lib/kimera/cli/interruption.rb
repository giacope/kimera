# frozen_string_literal: true

require_relative "outcome"

module Kimera
  class CLI
  end
end

class Kimera::CLI::Interruption
  def initialize(leader = Process.pid)
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
    text = "kimera: interrupted (SIG#{Signal.signame(signo)}); the test processes it started are stopped"
    Kimera::CLI::Outcome::Failed.new(128 + signo, text)
  end
end
