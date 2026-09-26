# frozen_string_literal: true

module Kimera
end

class Kimera::CLI
end

module Kimera::CLI::Argv
  module_function

  def option?(args, name) = args.any? { |arg| arg == name || arg.start_with?("#{name}=") }

  def any?(args, names) = names.any? { |name| option?(args, name) }
end
