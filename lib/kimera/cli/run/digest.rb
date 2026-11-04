# frozen_string_literal: true

require_relative "../../results/run_report"
require_relative "emission"

class Kimera::CLI::Run::Digest
  def initialize(emission:, io: $stdout)
    @io = io
    @emission = emission
  end

  def emit(...) = @emission.emit(...)

  def announce(change, selected, ignored, files:)
    change.announce(@io, selected, files)
    @io.puts("Ignoring #{ignored.size} mutant(s) marked equivalent.") unless ignored.empty?
  end

  def evaluating(ignored)
    return if ignored.empty?
    @io.puts("Evaluating them anyway (--evaluate-ignored): each keeps status ignored and records its verdict.")
  end

  def verbose(settings) = @io.puts("Kimera: #{settings}")
end
