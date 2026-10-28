# frozen_string_literal: true

class Kimera::Unguarded::Caught
  def initialize(guarded)
    @guarded = guarded
  end

  def clause = guarded.copy(exceptions: listed.type == :array_node ? listed.elements : [])

  def listed = guarded.exceptions.fetch(0).expression.body.body.fetch(0)

  private

  attr_reader :guarded
end
