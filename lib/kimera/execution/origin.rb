# frozen_string_literal: true

module Kimera
  module Execution
  end
end

class Kimera::Execution::Origin
  def initialize(path)
    @path = path
  end

  def canonical = path && File.exist?(path) ? File.realpath(path) : path

  private

  attr_reader :path
end
