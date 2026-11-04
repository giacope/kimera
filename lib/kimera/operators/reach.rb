# frozen_string_literal: true

module Kimera
  module Operators
  end
end

class Kimera::Operators::Reach
  def initialize(statement:, body:, toggles:)
    @statement = statement
    @body = body
    @toggles = toggles
  end

  def admits?(inside, position) = (inside || @body) && (position || !@statement)

  def withheld? = !@body && !@statement

  def toggles? = @toggles
end
