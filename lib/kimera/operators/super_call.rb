# frozen_string_literal: true

require_relative "base"
require_relative "enclosed"

class Kimera::Operators::SuperCall < Kimera::Operators::Base
  CALLS = [SuperNode, ForwardingSuperNode].freeze
  CALL = ->(node) { CALLS.any? { |kind| node.is_a?(kind) } }
  COERCED = %i[respond_to_missing?].freeze

  def initialize(coerced = Kimera::Operators::Survey::NONE)
    super()
    @coerced = coerced
  end

  def key = "super_call"

  def survey(root) = self.class.new(Kimera::Operators::Enclosed.new(root, COERCED, &CALL))

  def variants(node, **)
    deletion(node) if CALL.call(node) && !@coerced.include?(node)
  end
end
