# frozen_string_literal: true

require "prism"
require_relative "base"

class Kimera::Operators::ArgumentDrop < Kimera::Operators::Base
  SKIP_KINDS = [SplatNode, KeywordHashNode, BlockArgumentNode, ForwardingArgumentsNode].freeze

  def key = "argument_drop"

  def variants(node, **)
    return unless identifier?(node)
    words = arguments(node)
    return if words.any? { |a| SKIP_KINDS.any? { |k| a.is_a?(k) } }
    drops(words, "drop_argument", label: "drop arg")
  end
end
