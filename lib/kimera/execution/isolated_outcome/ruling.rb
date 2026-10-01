# frozen_string_literal: true

require "json"

class Kimera::Execution::IsolatedOutcome::Ruling
  OUTCOME = Kimera::Execution::IsolatedOutcome
  HEAD_LINES = 5
  TAIL_LINES = 15

  def initialize(exit, path, stderr = "")
    @exit = exit
    @path = path
    @stderr = stderr
  end

  def outcome
    return OUTCOME.new(:timeout) if @exit == :timeout
    ledger = read
    return unreported unless ledger
    tally(ledger)
  end

  private

  def unreported
    OUTCOME.new(:harness_error, nil, "test child #{status} without reporting results#{tail}")
  end

  def tail
    lines = @stderr.to_s.strip.lines(chomp: true)
    lines.empty? ? "" : ":\n#{ends(lines).join("\n")}"
  end

  def ends(lines)
    return lines if lines.size <= HEAD_LINES + TAIL_LINES
    [*lines.first(HEAD_LINES), "…", *lines.last(TAIL_LINES)]
  end

  def status
    code = @exit.exitstatus
    code ? "exited #{code}" : "died on signal #{@exit.termsig}"
  end

  def tally(ledger)
    failing = Array(ledger["failing"])
    return OUTCOME.new(:killed, failing, ledger["load_error"]) if ledger["failures"].positive?
    return OUTCOME.new(:survived) if @exit.success?
    OUTCOME.new(:harness_error, nil, unexplained)
  end

  def unexplained
    "suite #{status} with 0 failures " \
      "(a coverage floor or exit hook? skip it when ENV[\"KIMERA\"] is set)"
  end

  def read
    ledger = JSON.parse(File.read(@path, encoding: Encoding::UTF_8))
    ledger if ledger.is_a?(Hash) && ledger["failures"].is_a?(Integer)
  rescue Errno::ENOENT, JSON::ParserError
    nil
  end
end
