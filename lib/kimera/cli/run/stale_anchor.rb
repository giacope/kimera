# frozen_string_literal: true

module Kimera
end

class Kimera::CLI
end

class Kimera::CLI::Run
end

class Kimera::CLI::Run::StaleAnchor
  def initialize(rule)
    @rule = rule
  end

  def to_s
    kind = @rule[:starts] ? "kimera:disable comment" : "ignore entry"
    spot = [@rule[:file], @rule[:line] || @rule[:starts]].compact.join(":")
    "kimera: warning: #{kind} matches no mutant (stale anchor?): #{spot} #{@rule[:label]}".rstrip
  end
end
