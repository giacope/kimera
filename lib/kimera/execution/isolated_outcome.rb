# frozen_string_literal: true

require "json"

module Kimera
  module Execution
  end
end

class Kimera::Execution::IsolatedOutcome
  HEAD_LINES = 5
  TAIL_LINES = 15

  attr_reader :status, :failing, :detail

  def initialize(status, failing = nil, detail = nil)
    @status = status
    @failing = failing
    @detail = detail
  end

  class << self
    def judge(exit, path, stderr = "")
      return new(:timeout) if exit == :timeout
      ledger = read(path)
      return unreported(exit, stderr) unless ledger
      tally(exit, ledger)
    end

    private

    def unreported(exit, stderr)
      new(:harness_error, nil, "test child #{status_of(exit)} without reporting results#{tail(stderr)}")
    end

    def tail(stderr)
      lines = stderr.to_s.strip.lines(chomp: true)
      lines.empty? ? "" : ":\n#{ends(lines).join("\n")}"
    end

    def ends(lines)
      return lines if lines.size <= HEAD_LINES + TAIL_LINES
      [*lines.first(HEAD_LINES), "…", *lines.last(TAIL_LINES)]
    end

    def status_of(exit)
      code = exit.exitstatus
      code ? "exited #{code}" : "died on signal #{exit.termsig}"
    end

    def tally(exit, ledger)
      failing = Array(ledger["failing"])
      return new(:killed, failing) if ledger["failures"].positive?
      return new(:survived) if exit.success?
      new(:harness_error, nil, unexplained(exit))
    end

    def unexplained(exit)
      "suite #{status_of(exit)} with 0 failures " \
        "(a coverage floor or exit hook? skip it when ENV[\"KIMERA\"] is set)"
    end

    def read(path)
      ledger = JSON.parse(File.read(path, encoding: Encoding::UTF_8))
      ledger if ledger.is_a?(Hash) && ledger["failures"].is_a?(Integer)
    rescue Errno::ENOENT, JSON::ParserError
      nil
    end
  end
end
