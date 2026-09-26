# frozen_string_literal: true

class Kimera::CLI::Skill
  PATH = File.expand_path("../../../skills/kimera/SKILL.md", __dir__)

  def initialize(io: $stdout, errors: $stderr)
    @io = io
    @errors = errors
  end

  def run(argv)
    return usage unless argv.empty?
    @io.write(File.read(PATH))
    0
  end

  private

  def usage
    @errors.puts("kimera: usage: kimera skill")
    1
  end
end
