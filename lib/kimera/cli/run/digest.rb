# frozen_string_literal: true

require_relative "../../results/run_report"
require_relative "emission"

class Kimera::CLI::Run::Digest
  def initialize(emission:, io: $stdout)
    @io = io
    @emission = emission
  end

  def emit(...) = @emission.emit(...)

  def announce(selected, ignored, files:, since:)
    incremental(selected, files, since) if selected
    @io.puts("Ignoring #{ignored.size} mutant(s) marked equivalent.") unless ignored.empty?
  end

  def evaluating(ignored)
    return if ignored.empty?
    @io.puts("Evaluating them anyway (--evaluate-ignored): each keeps status ignored and records its verdict.")
  end

  def verbose(options)
    @io.puts(
      "Kimera: framework=#{options[:framework]} jobs=#{options[:jobs]} " \
        "sources=#{Array(options[:paths]).join(",")} tests=#{Array(options[:tests]).join(",")} " \
        "format=#{options.fetch(:format, "text")}"
    )
  end

  private

  def incremental(selected, files, since)
    @io.puts("Incremental: #{selected.size} mutants on lines changed since #{since} (#{files} changed files).")
  end
end
