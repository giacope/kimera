# frozen_string_literal: true

require_relative "base"

class Kimera::Operators::NilLiteral < Kimera::Operators::Base
  JUMPS = [ReturnNode, NextNode, BreakNode].freeze

  def key = "nil_literal"

  def variants(node, position:)
    return solo("nil => Object.new", "nil_object") if node.is_a?(NilNode) && position == :tail
    solo("#{node.keyword_loc.slice} nil => #{node.keyword_loc.slice} Object.new", "nil_object") if jump?(node)
  end

  private

  def jump?(node) = JUMPS.any? { |kind| node.is_a?(kind) } && (arguments(node) in [NilNode])
end
