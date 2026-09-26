# frozen_string_literal: true

module Kimera
end

class Kimera::CLI
end

class Kimera::CLI::Completion
  SCRIPTS = {
    "bash" => "_kimera() { COMPREPLY=( $(compgen -W '%s' -- \"${COMP_WORDS[1]}\") ); }\ncomplete -F _kimera kimera",
    "zsh" => "#compdef kimera\n_arguments '1:command:(%s)'",
    "fish" => "complete -c kimera -f -a '%s'"
  }.freeze
  SHELLS = SCRIPTS.keys.freeze

  def initialize(io: $stdout, errors: $stderr)
    @io = io
    @errors = errors
  end

  def run(argv)
    shell = argv.first
    return usage unless SHELLS.include?(shell) && argv.size == 1
    @io.puts(script(shell))
    0
  end

  private

  def usage
    @errors.puts("kimera: usage: kimera completion <#{SHELLS.join("|")}>")
    1
  end

  def script(shell) = format(SCRIPTS.fetch(shell), Kimera::CLI::COMMAND_NAMES.join(" "))
end
