# frozen_string_literal: true

require "json"

module Kimera
  module Execution
  end
end

class Kimera::Execution::IsolatedOutcome
  LEDGER = "KIMERA_ISOLATED_LEDGER"

  attr_reader :status, :failing, :detail

  def initialize(status, failing = nil, detail = nil)
    @status = status
    @failing = failing
    @detail = detail
  end

  class << self
    def judge(exit, path)
      return new(:timeout) if exit == :timeout
      ledger = read(path)
      return unreported(exit) unless ledger
      tally(exit, ledger)
    end

    private

    def unreported(exit) = new(exit.success? ? :survived : :killed)

    def tally(exit, ledger)
      failing = Array(ledger["failing"])
      return new(:killed, failing) if ledger["failures"].positive?
      return new(:survived) if exit.success?
      new(:harness_error, nil, unexplained(exit))
    end

    def unexplained(exit)
      "suite exited #{exit.exitstatus || "on signal #{exit.termsig}"} with 0 failures " \
        "(a coverage floor or exit hook? skip it when ENV[\"KIMERA\"] is set)"
    end

    def read(path)
      ledger = JSON.parse(File.read(path))
      ledger if ledger.is_a?(Hash) && ledger["failures"].is_a?(Integer)
    rescue Errno::ENOENT, JSON::ParserError
      nil
    end
  end
end
