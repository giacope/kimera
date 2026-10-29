# frozen_string_literal: true

require_relative "outcome"

class Kimera::CLI::Skill
  PATH = File.expand_path("../../../skills/kimera/SKILL.md", __dir__)

  def initialize(**); end

  def run(argv)
    return usage unless argv.empty?
    Kimera::CLI::Outcome::Written.new(File.read(PATH, encoding: Encoding::UTF_8))
  end

  private

  def usage = Kimera::CLI::Outcome::Failed.new(1, "kimera: usage: kimera skill")
end
