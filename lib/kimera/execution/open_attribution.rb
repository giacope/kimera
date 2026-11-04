# frozen_string_literal: true

module Kimera
  module Execution
  end
end

class Kimera::Execution::OpenAttribution
  def strict? = false

  def admits?(_source, &) = true
end
