# frozen_string_literal: true

require_relative "../../error"

class Kimera::CLI::Baseline::Setting
  LINE = /^#?[ \t]*baseline:.*$/

  def initialize(config)
    @config = config
  end

  def apply(output)
    raise(Kimera::UsageError, "no #{@config} to set the baseline in (run kimera init first)") unless File.file?(@config)
    text = File.read(@config)
    line = "baseline: #{output}"
    File.write(@config, text.match?(LINE) ? text.sub(LINE, line) : "#{text.chomp}\n#{line}\n")
  end
end
