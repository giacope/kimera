# frozen_string_literal: true

require_relative "gate"
require_relative "stale_anchor"

class Kimera::CLI::Run::Alerts
  MOVED = "kimera: warning: ignore entry re-anchored: %s (update the entry to silence this)"

  def initialize(errors: $stderr)
    @errors = errors
  end

  def gate(report, options) = Kimera::CLI::Run::Gate.new(report, options).status(@errors)

  def anchors(resolution) = resolution.alert(self)

  def stale(rule) = @errors.puts(Kimera::CLI::Run::StaleAnchor.new(rule))

  def moved(shift) = @errors.puts(format(MOVED, shift))
end
