# frozen_string_literal: true

class Kimera::CLI::Run::Targets
  PATTERN = /\A(?<path>.+?):(?<from>\d+)(?:-(?<to>\d+))?\z/

  def initialize(arguments)
    @arguments = arguments
  end

  def paths = @arguments.map { |argument| aims(argument).map { |match| match[:path] }.fetch(0, argument) }

  def lines
    @arguments.flat_map { |argument| aims(argument) }.each_with_object({}) do |match, found|
      from = match[:from]
      (found[match[:path]] ||= Set.new).merge(Integer(from, 10)..Integer(match[:to] || from, 10))
    end
  end

  private

  def aims(argument)
    match = PATTERN.match(argument)
    match && File.file?(match[:path]) ? [match] : []
  end
end
