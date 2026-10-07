# frozen_string_literal: true

class Kimera::CLI::Run::Targets
  PATTERN = /\A(?<path>.+?):(?<from>\d+)(?:-(?<to>\d+))?\z/

  def initialize(args)
    @args = args
  end

  def paths = @args.map { |arg| aimed(arg)&.[](:path) || arg }

  def lines
    @args.filter_map { |arg| aimed(arg) }.each_with_object({}) do |match, found|
      from = match[:from]
      (found[match[:path]] ||= Set.new).merge(Integer(from, 10)..Integer(match[:to] || from, 10))
    end
  end

  private

  def aimed(arg)
    match = PATTERN.match(arg)
    match if match && File.file?(match[:path])
  end
end
