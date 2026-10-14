# frozen_string_literal: true

module Kimera
end

class Kimera::CLI
end

module Kimera::CLI::Argv
  module_function

  def option?(arguments, name) = arguments.any? { |argument| argument == name || argument.start_with?("#{name}=") }

  def any?(arguments, names) = names.any? { |name| option?(arguments, name) }
end
