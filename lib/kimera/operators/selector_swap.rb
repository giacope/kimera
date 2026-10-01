# frozen_string_literal: true

require_relative "base"

class Kimera::Operators::SelectorSwap < Kimera::Operators::Base
  SWAPS = { select: :reject, reject: :select, filter_map: :map }
    .merge({ all?: :any?, any?: :all? })
    .merge({ min: :max, max: :min })
    .merge({ first: :last, last: :first })
    .merge({ detect: :first, find: :first })
    .freeze

  def key = "selector_swap"

  def variants(node, **)
    return unless node.is_a?(CallNode) && node.receiver
    name = node.name
    to = SWAPS[name]
    return unless to
    solo("#{name} => #{to}", "selector_swap", to: to.to_s)
  end
end
