# frozen_string_literal: true

require_relative "outcome"

class Kimera::CLI::Verdict
  def initialize(checks)
    @checks = checks
  end

  def outcome
    failed = @checks.count { |status,| status == "✗" }
    return Kimera::CLI::Outcome::Ended.new(0) if failed.zero?
    Kimera::CLI::Outcome::Failed.new(1, "kimera: doctor found #{failed} blocking issue(s)")
  end
end
