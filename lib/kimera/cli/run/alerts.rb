# frozen_string_literal: true

require_relative "gate"

class Kimera::CLI::Run::Alerts
  MOVED = "kimera: warning: ignore entry re-anchored: %s (update the entry to silence this)"

  def initialize(errors: $stderr)
    @errors = errors
  end

  def gate(report, options) = Kimera::CLI::Run::Gate.new(report, options).status(@errors)

  def anchors(resolution)
    resolution.stale.each { |rule| @errors.puts(anchor(rule)) }
    resolution.moved.each { |shift| @errors.puts(format(MOVED, shift)) }
  end

  private

  def anchor(rule)
    kind = rule[:starts] ? "kimera:disable comment" : "ignore entry"
    spot = [rule[:file], rule[:line] || rule[:starts]].compact.join(":")
    "kimera: warning: #{kind} matches no mutant (stale anchor?): #{spot} #{rule[:label]}".rstrip
  end
end
