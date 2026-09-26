# frozen_string_literal: true

require_relative "base"

class Kimera::Operators::IndexFetch < Kimera::Operators::Base
  class << self
    def key = "index_fetch"
  end

  def variants(node, **)
    return unless call(node).chained?(:[])
    return unless unary?(node)
    solo("[] => fetch", "index_to_fetch")
  end
end
