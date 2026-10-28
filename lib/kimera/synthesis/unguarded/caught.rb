# frozen_string_literal: true

class Kimera::Unguarded::Caught
  def initialize(guarded)
    @guarded = guarded
  end

  def clause = guarded.copy(exceptions: listed.type == :array_node ? listed.elements : [])

  def listed = guarded.exceptions.first.expression.body.body.first

  private

  attr_reader :guarded
end
