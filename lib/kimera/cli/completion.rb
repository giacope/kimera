# frozen_string_literal: true

require_relative "outcome"

module Kimera
end

class Kimera::CLI
  class Completion
    SCRIPTS = {
      "bash" => "_kimera() { COMPREPLY=( $(compgen -W '%s' -- \"${COMP_WORDS[1]}\") ); }\ncomplete -F _kimera kimera",
      "zsh" => "#compdef kimera\n_arguments '1:command:(%s)'",
      "fish" => "complete -c kimera -f -a '%s'"
    }.freeze
    SHELLS = SCRIPTS.keys.freeze

    def initialize(**); end

    def run(argv)
      shell = argv.first
      return usage unless SHELLS.include?(shell) && argv.size == 1
      Kimera::CLI::Outcome::Said.new(script(shell))
    end

    private

    def usage
      Kimera::CLI::Outcome::Failed.new(1, "kimera: usage: kimera completion <#{SHELLS.join("|")}>")
    end

    def script(shell) = format(SCRIPTS.fetch(shell), COMMAND_NAMES.join(" "))
  end
end
