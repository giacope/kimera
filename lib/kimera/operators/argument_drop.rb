# frozen_string_literal: true

require "prism"
require_relative "base"

class Kimera::Operators::ArgumentDrop < Kimera::Operators::Base
  SKIP_KINDS = [SplatNode, KeywordHashNode, BlockArgumentNode, ForwardingArgumentsNode].freeze

  class << self
    def key = "argument_drop"
  end

  def variants(node, **)
    return unless identifier?(node)
    args = arguments(node)
    return if args.any? { |a| SKIP_KINDS.any? { |k| a.is_a?(k) } }
    drops(args, "drop_argument", label: "drop arg")
  end
end
