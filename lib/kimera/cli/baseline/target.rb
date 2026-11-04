# frozen_string_literal: true

require "yaml"
require_relative "../../error"
require_relative "../../scope/config"
require_relative "../outcome"

class Kimera::CLI::Baseline::Target
  def initialize(output, force, write)
    @output = output
    @force = force
    @write = write
  end

  def checked
    overwrite if File.exist?(@output) && !@force
    self
  end

  def saved(ignored)
    File.write(@output, YAML.dump("format_version" => 1, "ignore" => ignored))
    set if @write
    created(ignored.size)
  end

  private

  def overwrite = raise(Kimera::UsageError, "#{@output} already exists (use --force to replace it)")

  def set = Kimera::CLI::Baseline::Setting.new(config).apply(@output)

  def created(count) = Kimera::CLI::Outcome::Said.new("Created #{@output} with #{count} accepted survivor(s).", applied)

  def applied
    return "Set `baseline: #{@output}` in #{config}." if @write
    "Add `baseline: #{@output}` to .kimera.yml to apply it, or rerun with --write."
  end

  def config = Kimera::Config.of(".").to_s
end
