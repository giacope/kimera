# frozen_string_literal: true

require_relative "base"

class Kimera::Operators::IndexFetch < Kimera::Operators::Base
  def key = "index_fetch"

  def variants(node, **)
    return unless call(node).chained?(:[])
    return unless unary?(node)
    solo("[] => fetch", "index_to_fetch")
  end
end
