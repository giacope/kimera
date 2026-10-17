# frozen_string_literal: true

require_relative "base"
require_relative "enclosed"

class Kimera::Operators::SuperCall < Kimera::Operators::Base
  CALLS = [SuperNode, ForwardingSuperNode].freeze
  CALL = ->(node) { CALLS.any? { |kind| node.is_a?(kind) } }
  COERCED = %i[respond_to_missing?].freeze

  def key = "super_call"

  def survey(root)
    @_coerced = Kimera::Operators::Enclosed.new(root, COERCED, &CALL)
    self
  end

  def variants(node, **)
    deletion(node) if CALL.call(node) && !coerced.include?(node)
  end

  private

  def coerced = @_coerced || Kimera::Operators::Survey::NONE
end
