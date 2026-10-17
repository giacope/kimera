# frozen_string_literal: true

module Kimera
end

class Kimera::CLI
end

class Kimera::CLI::Argv
  def initialize(arguments)
    @arguments = arguments
  end

  def option?(name) = @arguments.any? { |argument| argument == name || argument.start_with?("#{name}=") }

  def any?(names) = names.any? { |name| option?(name) }
end
