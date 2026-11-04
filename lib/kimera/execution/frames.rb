# frozen_string_literal: true

module Kimera
  module Execution
  end
end

class Kimera::Execution::Frames
  MAX_FRAMES = 12
  HARNESS = File.expand_path("..", __dir__)

  def initialize(frames)
    @frames = frames
  end

  def own = @frames.take_while { |frame| !frame.start_with?(HARNESS) }

  def lines(here = Dir.pwd) = @frames.first(MAX_FRAMES).map { |frame| "  #{frame.delete_prefix("#{here}/")}" }

  def hidden = @frames.size - MAX_FRAMES
end
