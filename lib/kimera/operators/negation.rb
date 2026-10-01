# frozen_string_literal: true

require_relative "base"

class Kimera::Operators::Negation < Kimera::Operators::Base
  def key = "negation"

  def variants(node, **)
    return unless call(node).chained?(:!)
    return if node.arguments
    solo("delete !", "unwrap_receiver")
  end
end
