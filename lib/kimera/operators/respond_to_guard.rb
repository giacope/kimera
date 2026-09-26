# frozen_string_literal: true

require_relative "base"

class Kimera::Operators::RespondToGuard < Kimera::Operators::Base
  class << self
    def key = "respond_to_guard"
  end

  def variants(node, **)
    return unless guard?(node)
    solo("delete .respond_to?", "unwrap_receiver")
  end

  private

  def guard?(node)
    return false unless call(node).chained?(:respond_to?) && !node.block
    args = arguments(node)
    return false unless (1..2).cover?(args.length)
    target = args.first
    target.is_a?(SymbolNode) || target.is_a?(StringNode)
  end
end
