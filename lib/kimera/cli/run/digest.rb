# frozen_string_literal: true

require_relative "../../results/run_report"
require_relative "../../scope/ignore_list"
require_relative "emission"
require_relative "gate"

class Kimera::CLI::Run::Digest
  def initialize(emission:, io: $stdout, errors: $stderr)
    @io = io
    @errors = errors
    @emission = emission
  end

  def emit(...) = @emission.emit(...)

  def gate(report, options) = Kimera::CLI::Run::Gate.new(report, options).status(@errors)

  def announce(selected, ignored, files:, since:)
    incremental(selected, files, since) if selected
    @io.puts("Ignoring #{ignored.size} mutant(s) marked equivalent.") unless ignored.empty?
  end

  def stale(registry, rules)
    Kimera::IgnoreList.stale(registry, rules).each { |rule| @errors.puts(anchor(rule)) }
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

  def anchor(rule)
    "kimera: warning: ignore entry matches no mutant (stale anchor?): #{spot(rule)} #{rule[:label]}".rstrip
  end

  def spot(rule)
    [rule[:file], rule[:line]].compact.join(":")
  end
end
