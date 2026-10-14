# frozen_string_literal: true

class Kimera::CLI::Run::Targets
  PATTERN = /\A(?<path>.+?):(?<from>\d+)(?:-(?<to>\d+))?\z/

  def initialize(arguments)
    @arguments = arguments
  end

  def paths = @arguments.map { |argument| aimed(argument)&.[](:path) || argument }

  def lines
    @arguments.filter_map { |argument| aimed(argument) }.each_with_object({}) do |match, found|
      from = match[:from]
      (found[match[:path]] ||= Set.new).merge(Integer(from, 10)..Integer(match[:to] || from, 10))
    end
  end

  private

  def aimed(argument)
    match = PATTERN.match(argument)
    match if match && File.file?(match[:path])
  end
end
